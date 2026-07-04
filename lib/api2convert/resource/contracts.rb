# frozen_string_literal: true

module Api2Convert
  module Resource
    # Information about the account's active contracts (free-form response).
    class Contracts
      def initialize(transport)
        @transport = transport
      end

      def get
        @transport.request("GET", "/contracts")
      end
    end
  end
end
