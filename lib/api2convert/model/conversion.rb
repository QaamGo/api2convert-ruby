# frozen_string_literal: true

module Api2Convert
  module Model
    # A single conversion within a job: the target format plus its options.
    class Conversion
      attr_reader :target, :id, :category, :options, :metadata, :output_targets

      def initialize(target: "", id: nil, category: nil, options: {}, metadata: {},
                     output_targets: [])
        @target = target
        @id = id
        @category = category
        @options = options
        @metadata = metadata
        # Cloud delivery targets for this conversion's output, if any.
        @output_targets = output_targets
        freeze
      end

      def self.from_hash(data)
        d = Support::Data.as_object(data)
        new(
          target: Support::Data.as_str(d["target"]),
          id: Support::Data.nullable_str(d["id"]),
          category: Support::Data.nullable_str(d["category"]),
          options: Support::Data.as_object(d["options"]),
          metadata: Support::Data.as_object(d["metadata"]),
          output_targets: Support::Data.map_objects(d["output_target"]) { |x| OutputTarget.from_hash(x) }
        )
      end
    end
  end
end
