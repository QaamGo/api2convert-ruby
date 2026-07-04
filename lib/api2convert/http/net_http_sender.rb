# frozen_string_literal: true

require "net/http"
require "uri"
require "openssl"

module Api2Convert
  module Http
    # The default {HttpSender}, built on Ruby's stdlib `Net::HTTP` (zero runtime
    # dependencies).
    #
    # `Net::HTTP` does not follow redirects on its own — this SDK relies on that.
    # A request only follows a 3xx when {Request#follow_redirects} is true (the
    # no-secret download path); a redirect is then re-issued as a bare GET carrying
    # only `Accept`/`User-Agent`, so a custom `X-Oc-*` secret header can never be
    # forwarded to the redirect target.
    #
    # An {HttpSender} is any object responding to `call(request) -> Response`. Unit
    # tests inject a fake in its place; this real sender is exercised end-to-end by
    # the independent security suite against loopback servers.
    class NetHttpSender
      MAX_REDIRECTS = 5
      REDIRECT_CODES = [301, 302, 303, 307, 308].freeze

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
          request.follow_redirects, 0
        )
      end

      private

      def perform(method, url, headers, body, body_stream, content_length, follow, hops)
        uri = URI.parse(url)
        raise Api2Convert::NetworkError, "Unsupported or non-HTTP URL: #{url}" unless uri.is_a?(URI::HTTP)

        http = build_http(uri)
        req = build_request(method, uri, headers, body, body_stream, content_length)
        res = http.start { |conn| conn.request(req) }
        status = res.code.to_i

        if follow && REDIRECT_CODES.include?(status) && hops < MAX_REDIRECTS
          location = res["location"]
          unless location.nil? || location.empty?
            # Re-issue as a bare GET carrying only non-secret headers, so no
            # X-Oc-* secret header is ever forwarded to the redirect target.
            safe = {}
            %w[Accept User-Agent].each { |k| safe[k] = headers[k] unless headers[k].nil? }
            next_url = URI.join(url, location).to_s
            return perform("GET", next_url, safe, nil, nil, nil, follow, hops + 1)
          end
        end

        to_response(res)
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

      def to_response(res)
        headers = {}
        res.each_header { |key, value| headers[key.downcase] = value }
        Response.new(res.code.to_i, headers, res.body || "", res.message.to_s)
      end
    end
  end
end
