# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "socket"
require "time"
require "timeout"
require "uri"

module Api2Convert
  module Http
    # The HTTP layer: authenticated requests, transient-failure retries with
    # exponential backoff, error-response mapping to typed exceptions, and JSON
    # decoding.
    #
    # Resources talk to the API through {#request}; the uploader and the
    # downloader use {#send_request} / {#interpret} directly because they need
    # non-JSON bodies and per-job auth. Internal.
    class Transport
      RETRYABLE_STATUSES = [429, 500, 502, 503, 504].freeze
      IDEMPOTENT_METHODS = %w[GET HEAD PUT DELETE OPTIONS TRACE].freeze
      MAX_BACKOFF_SECONDS = 8.0
      # Upper bound for an honored `Retry-After` — a hostile/misconfigured value
      # asking for an absurd delay can never stall a worker for hours.
      MAX_RETRY_AFTER_SECONDS = 120.0

      # Transport-level failures worth wrapping as {NetworkError} (and retrying,
      # for idempotent requests). `SystemCallError` covers the `Errno::*` family.
      TRANSPORT_ERRORS = [
        SocketError, SystemCallError, IOError, EOFError,
        Timeout::Error, OpenSSL::SSL::SSLError, URI::Error,
        Net::OpenTimeout, Net::ReadTimeout, Net::HTTPBadResponse, Net::ProtocolError
      ].freeze

      attr_reader :config

      def initialize(sender, config, sleeper: nil, rng: nil)
        @sender = sender
        @config = config
        @sleeper = sleeper || ->(seconds) { Kernel.sleep(seconds) }
        @rng = rng || -> { Kernel.rand }
      end

      # Sleep for (at least) +seconds+ with a small upward jitter. Used by job
      # polling; the jitter keeps a fleet from polling in lockstep.
      def pause(seconds)
        @sleeper.call(jitter(seconds))
      end

      # Perform an authenticated JSON request and return the decoded body.
      def request(method, path, body = nil, query = nil, headers = nil)
        request_headers = { "X-Oc-Api-Key" => @config.api_key }
        request_headers.merge!(headers) unless headers.nil?
        content = nil
        unless body.nil?
          content = JSON.generate(body)
          request_headers["Content-Type"] = "application/json"
        end
        url = build_url(path, query)

        build = lambda do
          Request.new(method: method, url: url, headers: request_headers.dup, body: content)
        end
        interpret(send_request(build))
      end

      # Send a request (rebuilt fresh each attempt) with retry/backoff. +build+
      # returns a fresh {Request} — a retry re-invokes it so a seekable body is
      # replayed from the start. Adds the common `Accept`/`User-Agent` headers but
      # no auth (callers add the header they need). +replayable+ must be false for
      # a non-seekable body so it is sent once.
      #
      # +follow_redirects+ defaults to false: authenticated requests carry a secret
      # in a custom `X-Oc-*` header, which a redirect could leak to another host.
      # Only the self-contained download path (no account key) opts in.
      def send_request(build, replayable: true, follow_redirects: false)
        attempt = 0
        loop do
          request = build.call
          request.headers["Accept"] = "application/json"
          request.headers["User-Agent"] = user_agent
          request.follow_redirects = follow_redirects
          idempotent = idempotent?(request)

          begin
            response = @sender.call(request)
          rescue *TRANSPORT_ERRORS => e
            # A non-idempotent request must not be replayed on a network error:
            # the backend may already have acted, so a blind retry could create a
            # duplicate job (and a duplicate charge).
            if replayable && idempotent && attempt < @config.max_retries
              backoff(attempt)
              attempt += 1
              next
            end
            raise NetworkError, "Request to API2Convert failed: #{e.message}"
          end

          status = response.status
          may_retry = RETRYABLE_STATUSES.include?(status) && replayable &&
                      attempt < @config.max_retries && (status == 429 || idempotent)
          if may_retry
            backoff(attempt, response.header("retry-after"))
            attempt += 1
            next
          end

          return response
        end
      end

      # Raise a typed exception for error responses; otherwise decode JSON.
      def interpret(response)
        ensure_successful(response)

        raw = response.body
        return {} if raw.nil? || raw.empty?

        begin
          decoded = JSON.parse(raw)
        rescue JSON::ParserError => e
          # A 2xx carrying a non-JSON body (e.g. an intermediary HTML page) must
          # surface as an SDK exception, not a raw parser error escaping the tree.
          raise NetworkError, "API2Convert returned a non-JSON success response: #{e.message}"
        end
        decoded.is_a?(Hash) || decoded.is_a?(Array) ? decoded : {}
      end

      # Raise the appropriate typed exception when +response+ is an HTTP error.
      def ensure_successful(response)
        status = response.status
        return if status < 400

        body = decode_safe(response)
        api_message = body["message"]
        message = api_message.is_a?(String) ? api_message : fallback_message(response)
        request_id = response.header("x-request-id")
        request_id = nil if request_id.nil? || request_id.empty?

        case status
        when 401, 403
          raise AuthenticationError.new(message, status_code: status, request_id: request_id, body: body)
        when 402
          raise PaymentRequiredError.new(message, status_code: status, request_id: request_id, body: body)
        when 404
          raise NotFoundError.new(message, status_code: status, request_id: request_id, body: body)
        when 429
          raise RateLimitError.new(
            message, status_code: status, request_id: request_id, body: body,
                     retry_after: parse_retry_after(response.header("retry-after"))
          )
        when 400, 422
          raise ValidationError.new(message, status_code: status, request_id: request_id, body: body)
        else
          if status >= 500
            raise ServerError.new(message, status_code: status, request_id: request_id, body: body)
          end

          raise ApiError.new(message, status_code: status, request_id: request_id, body: body)
        end
      end

      # Download a (self-contained) URL and return its bytes. Used for output
      # downloads — these URLs need no API key.
      #
      # +follow_redirects+ is true for a passwordless download (storage URLs
      # legitimately redirect, and no secret is carried) and false when a
      # download-password header is present (so it can never leak on a redirect).
      def download(uri, headers = {}, follow_redirects: true)
        request_headers = headers.nil? ? {} : headers
        build = lambda do
          Request.new(method: "GET", url: uri, headers: request_headers.dup)
        end
        response = send_request(build, replayable: true, follow_redirects: follow_redirects)
        ensure_successful(response)
        response.body
      end

      # Build a request object without sending it (used by the uploader, which
      # supplies a streamed multipart body).
      def build_request(method, url, headers: {}, body_stream: nil, content_length: nil)
        Request.new(
          method: method, url: url, headers: headers,
          body_stream: body_stream, content_length: content_length
        )
      end

      private

      def build_url(path, query)
        url = "#{@config.base_url}/#{path.sub(%r{\A/+}, "")}"
        url = "#{url}?#{URI.encode_www_form(query)}" if query && !query.empty?
        url
      end

      def decode_safe(response)
        raw = response.body
        return {} if raw.nil? || raw.empty?

        decoded = JSON.parse(raw)
        decoded.is_a?(Hash) ? decoded : {}
      rescue JSON::ParserError
        {}
      end

      def fallback_message(response)
        response.reason.to_s.empty? ? "Request failed" : response.reason
      end

      def backoff(attempt, retry_after = nil)
        retry_secs = parse_retry_after(retry_after)
        seconds =
          if retry_secs&.positive?
            # Honor a positive Retry-After (capped so a hostile value can't stall
            # us for hours). Not jittered: the server asked for this exact delay.
            [MAX_RETRY_AFTER_SECONDS, retry_secs.to_f].min
          else
            # A zero/absent Retry-After falls through to jittered exponential
            # backoff so we never retry-storm with no delay.
            jitter([MAX_BACKOFF_SECONDS, 0.5 * (2**attempt)].min)
          end
        @sleeper.call(seconds)
      end

      # Parse `Retry-After` (delay-seconds or HTTP-date) into whole seconds.
      # Returns nil when absent/unparseable; never negative.
      def parse_retry_after(value)
        return nil if value.nil? || value.empty?

        begin
          number = Float(value)
          # A non-finite value (e.g. "1e400" -> Infinity, "NaN") must not crash:
          # Float::INFINITY.to_i raises FloatDomainError. Fall through so a hostile
          # Retry-After can never stall a worker (matches Python's OverflowError guard).
          return [0, number.to_i].max if number.finite?
        rescue ArgumentError, TypeError
          # not a plain number — fall through to the HTTP-date form
        end

        begin
          parsed = Time.httpdate(value)
        rescue ArgumentError
          return nil
        end
        [0, (parsed - Time.now).to_i].max
      end

      # Add a small upward jitter (0-25%) so correlated clients don't lockstep.
      def jitter(seconds)
        seconds + (seconds * 0.25 * @rng.call)
      end

      def idempotent?(request)
        return true if IDEMPOTENT_METHODS.include?(request.method)

        !request.headers["Idempotency-Key"].to_s.empty?
      end

      def user_agent
        @user_agent ||= "api2convert-ruby/#{Api2Convert::VERSION} ruby/#{RUBY_VERSION}"
      end
    end
  end
end
