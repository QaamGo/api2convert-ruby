# frozen_string_literal: true

module Api2Convert
  module Model
    # A job's status: a machine-readable {#code} plus optional human {#info}.
    class Status
      attr_reader :code, :info

      def initialize(code: "", info: nil)
        @code = code
        @info = info
        freeze
      end

      def self.from_hash(data)
        d = Support::Data.as_object(data)
        new(
          code: Support::Data.as_str(d["code"]),
          info: Support::Data.nullable_str(d["info"])
        )
      end
    end
  end
end
