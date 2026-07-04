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
      attr_reader :method, :url, :headers, :body, :body_stream, :content_length
      # Whether the sender may follow a 3xx redirect. Set by the transport per
      # request: authenticated requests carry a secret in a custom `X-Oc-*` header,
      # so they must NOT follow redirects (the header could leak to another host).
      attr_accessor :follow_redirects

      def initialize(method:, url:, headers: {}, body: nil,
                     body_stream: nil, content_length: nil, follow_redirects: false)
        @method = method.to_s.upcase
        @url = url
        @headers = headers
        @body = body
        @body_stream = body_stream
        @content_length = content_length
        @follow_redirects = follow_redirects
      end
    end
  end
end
