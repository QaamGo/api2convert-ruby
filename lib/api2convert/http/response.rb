# frozen_string_literal: true

module Api2Convert
  module Http
    # A transport-agnostic HTTP response. Headers are stored with downcased keys
    # so {#header} lookups are case-insensitive regardless of the sender.
    class Response
      attr_reader :status, :headers, :body, :reason

      def initialize(status, headers, body, reason = "")
        @status = status
        @headers = headers || {}
        @body = body || ""
        @reason = reason || ""
      end

      # Case-insensitive header lookup. Returns nil when absent.
      def header(name)
        @headers[name.to_s.downcase]
      end
    end
  end
end
