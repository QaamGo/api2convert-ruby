# frozen_string_literal: true

module Api2Convert
  module Http
    # A transport-agnostic HTTP request. The {Transport} builds these and hands
    # them to an {HttpSender}; a retry rebuilds a fresh one so a seekable body is
    # replayed from the start.
    #
    # Exactly one of {#body} (a String) or {#body_stream} (an IO whose byte length
    # is {#content_length}) is set on a request with a payload.
    class Request
      attr_reader :method, :url, :headers, :body, :body_stream, :content_length, :response_sink
      # Whether the sender may follow a 3xx redirect. Set by the transport per
      # request: authenticated requests carry a secret in a custom `X-Api2convert-*` header,
      # so they must NOT follow redirects (the header could leak to another host).
      attr_accessor :follow_redirects

      def initialize(method:, url:, headers: {}, body: nil, body_stream: nil,
                     content_length: nil, follow_redirects: false, response_sink: nil)
        @method = method.to_s.upcase
        @url = url
        @headers = headers
        @body = body
        @body_stream = body_stream
        @content_length = content_length
        @follow_redirects = follow_redirects
        # An IO-like object (responds to `write`) to stream a successful download
        # body into, instead of buffering it whole. nil for a normal request.
        @response_sink = response_sink
      end

      # Redacted representation — {#headers} carries the raw `X-Api2convert-Api-Key` /
      # `X-Api2convert-Download-Password` secrets, so the default `#inspect` would print
      # them in cleartext in a log line or a backtrace. Mask every `X-Api2convert-*` value
      # (and the legacy `X-Oc-*` prefix, so a redaction gap can never open up).
      def inspect
        safe = @headers.to_h do |key, value|
          secret = key.to_s.downcase.start_with?("x-api2convert-", "x-oc-")
          [key, secret ? Support::Secret.mask(value) : value]
        end
        "#<#{self.class.name} method=#{@method.inspect} url=#{@url.inspect} headers=#{safe.inspect}>"
      end

      def to_s
        inspect
      end
    end
  end
end
