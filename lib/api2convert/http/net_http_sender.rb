# frozen_string_literal: true

require "net/http"
require "uri"
require "openssl"
require "timeout"

module Api2Convert
  module Http
    # The default {HttpSender}, built on Ruby's stdlib `Net::HTTP` (zero runtime
    # dependencies).
    #
    # `Net::HTTP` does not follow redirects on its own — this SDK relies on that.
    # A request only follows a 3xx when {Request#follow_redirects} is true (the
    # no-secret download path); a redirect is then re-issued as a bare GET carrying
    # only `Accept`/`User-Agent`, so a custom `X-Api2convert-*` secret header can never be
    # forwarded to the redirect target.
    #
    # An {HttpSender} is any object responding to `call(request) -> Response`. Unit
    # tests inject a fake in its place; this real sender is exercised end-to-end by
    # the independent security suite against loopback servers.
    class NetHttpSender
      MAX_REDIRECTS = 5
      REDIRECT_CODES = [301, 302, 303, 307, 308].freeze

      # Caps how much of a control-plane (API / error) JSON body the SDK buffers
      # into memory, so a hostile or buggy server cannot force an unbounded read
      # (OOM) on that path. Mirrors the shipped Go SDK's `maxResponseBytes = 16 <<
      # 20` (transport.go), whose readAllAndClose reads through an
      # io.LimitReader(rc, maxResponseBytes). File downloads are streamed straight
      # to the sink (never buffered) and bounded separately, so this cap covers the
      # buffered control-plane path only.
      MAX_RESPONSE_BYTES = 16 * 1024 * 1024 # 16 MiB

      # Errors worth surfacing when they strike mid-stream (after bytes have
      # already reached the sink). They are re-raised as {NetworkError} so the
      # transport does NOT retry — replaying would re-stream the whole body and
      # append it to the partial file, silently corrupting the download.
      #
      # This MUST stay a superset of {Transport::TRANSPORT_ERRORS}: any transport
      # error the retry loop would otherwise catch (notably OpenSSL::SSL::SSLError
      # on a truncated/reset TLS body) has to be intercepted here first, or an
      # idempotent streamed GET gets retried and the file is corrupted.
      STREAM_ERRORS = [
        IOError, EOFError, SocketError, SystemCallError, Timeout::Error,
        OpenSSL::SSL::SSLError, URI::Error,
        Net::OpenTimeout, Net::ReadTimeout, Net::HTTPBadResponse, Net::ProtocolError
      ].freeze

      METHOD_CLASSES = {
        "GET" => Net::HTTP::Get,
        "HEAD" => Net::HTTP::Head,
        "POST" => Net::HTTP::Post,
        "PUT" => Net::HTTP::Put,
        "PATCH" => Net::HTTP::Patch,
        "DELETE" => Net::HTTP::Delete,
        "OPTIONS" => Net::HTTP::Options
      }.freeze

      def initialize(timeout: 30)
        @timeout = timeout
      end

      def call(request)
        perform(
          request.method, request.url, request.headers,
          request.body, request.body_stream, request.content_length,
          request.follow_redirects, request.response_sink, 0
        )
      end

      private

      def perform(method, url, headers, body, body_stream, content_length, follow, sink, hops)
        uri = URI.parse(url)
        raise Api2Convert::NetworkError, "Unsupported or non-HTTP URL: #{url}" unless uri.is_a?(URI::HTTP)

        http = build_http(uri)
        req = build_request(method, uri, headers, body, body_stream, content_length)

        redirect_to = nil
        result = nil
        http.start do |conn|
          conn.request(req) do |res|
            status = res.code.to_i
            if follow && REDIRECT_CODES.include?(status) && hops < MAX_REDIRECTS &&
               !res["location"].to_s.empty?
              redirect_to = res["location"]
            elsif sink && status >= 200 && status < 300
              # Stream the success body straight to the sink — never buffered whole
              # in memory — and hand back an empty-body Response.
              stream_body(res, sink)
              result = to_response(res, "")
            else
              result = to_response(res, read_capped_body(res))
            end
          end
        end

        if redirect_to
          # Re-issue as a bare GET carrying only non-secret headers, so no X-Api2convert-*
          # secret header is ever forwarded to the redirect target.
          safe = {}
          %w[Accept User-Agent].each { |k| safe[k] = headers[k] unless headers[k].nil? }
          next_url = URI.join(url, redirect_to).to_s
          return perform("GET", next_url, safe, nil, nil, nil, follow, sink, hops + 1)
        end

        result
      end

      # Buffer a control-plane (API / error) response body into memory, bounded by
      # {MAX_RESPONSE_BYTES}. Because `Net::HTTP` is used in block form the body is
      # not read until this runs, so — unlike an SDK-side cap applied after a whole
      # `res.body` — we accumulate chunk-by-chunk and abort the instant the total
      # crosses the cap, before an over-cap body is ever fully resident. Mirrors the
      # Go SDK's io.LimitReader-wrapped read. Only the cap is raised here; genuine
      # transport errors propagate exactly as `res.body` would, so the retry loop
      # still classifies them.
      def read_capped_body(res)
        buffer = +""
        res.read_body do |chunk|
          buffer << chunk
          next unless buffer.bytesize > MAX_RESPONSE_BYTES

          raise Api2Convert::NetworkError, "API response body exceeds 16 MiB"
        end
        buffer
      end

      def stream_body(res, sink)
        res.read_body { |chunk| sink.write(chunk) }
      rescue *STREAM_ERRORS => e
        # A failure once bytes have flowed to the sink must not be retried: a replay
        # would append to a partial file and corrupt it. Raise a NetworkError (not a
        # retryable transport error) so the transport surfaces it directly and the
        # caller can delete the partial target.
        raise Api2Convert::NetworkError, "Download stream failed: #{e.message}"
      end

      def build_http(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.is_a?(URI::HTTPS)
        http.open_timeout = @timeout
        http.read_timeout = @timeout
        http.write_timeout = @timeout if http.respond_to?(:write_timeout=)
        # The SDK's own retry policy (in Transport) is the sole authority. Disable
        # Net::HTTP's built-in idempotent connection-error retry so requests are
        # never silently re-sent underneath us (double retries / duplicate hits).
        http.max_retries = 0 if http.respond_to?(:max_retries=)
        http
      end

      def build_request(method, uri, headers, body, body_stream, content_length)
        klass = METHOD_CLASSES[method]
        raise Api2Convert::NetworkError, "Unsupported HTTP method: #{method}" if klass.nil?

        req = klass.new(uri.request_uri)
        headers.each { |key, value| req[key] = value unless value.nil? }
        if body_stream
          req.body_stream = body_stream
          req["Content-Length"] = content_length.to_s unless content_length.nil?
        elsif body
          req.body = body
        end
        req
      end

      def to_response(res, body)
        headers = {}
        res.each_header { |key, value| headers[key.downcase] = value }
        Response.new(res.code.to_i, headers, body, res.message.to_s)
      end
    end
  end
end
