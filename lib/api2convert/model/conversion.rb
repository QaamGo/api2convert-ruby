# frozen_string_literal: true

module Api2Convert
  module Model
    # A single conversion within a job: the target format plus its options.
    class Conversion
      attr_reader :target, :id, :category, :options, :metadata

      def initialize(target: "", id: nil, category: nil, options: {}, metadata: {})
        @target = target
        @id = id
        @category = category
        @options = options
        @metadata = metadata
        freeze
      end

      def self.from_hash(data)
        d = Support::Data.as_object(data)
        new(
          target: Support::Data.as_str(d["target"]),
          id: Support::Data.nullable_str(d["id"]),
          category: Support::Data.nullable_str(d["category"]),
          options: Support::Data.as_object(d["options"]),
          metadata: Support::Data.as_object(d["metadata"])
        )
      end
    end
  end
end
