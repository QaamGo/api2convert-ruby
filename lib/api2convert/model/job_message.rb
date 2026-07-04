# frozen_string_literal: true

module Api2Convert
  module Model
    # An error or warning attached to a job (the `errors[]` / `warnings[]` entries).
    class JobMessage
      attr_reader :code, :message, :source, :id_source, :details

      def initialize(code: nil, message: "", source: nil, id_source: nil, details: {})
        @code = code
        @message = message
        @source = source
        @id_source = id_source
        @details = details
        freeze
      end

      def self.from_hash(data)
        d = Support::Data.as_object(data)
        new(
          code: Support::Data.nullable_int(d["code"]),
          message: Support::Data.as_str(d["message"]),
          source: Support::Data.nullable_str(d["source"]),
          id_source: Support::Data.nullable_str(d["id_source"]),
          details: Support::Data.as_object(d["details"])
        )
      end
    end
  end
end
