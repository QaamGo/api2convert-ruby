# frozen_string_literal: true

module Api2Convert
  module Model
    # A saved conversion preset (a reusable named set of target + options).
    class Preset
      attr_reader :id, :name, :target, :category, :scope, :options

      def initialize(id: nil, name: "", target: nil, category: nil, scope: nil, options: {})
        @id = id
        @name = name
        @target = target
        @category = category
        @scope = scope
        @options = options
        freeze
      end

      def self.from_hash(data)
        d = Support::Data.as_object(data)
        new(
          id: Support::Data.nullable_str(d["id"]),
          name: Support::Data.as_str(d["name"]),
          target: Support::Data.nullable_str(d["target"]),
          category: Support::Data.nullable_str(d["category"]),
          scope: Support::Data.nullable_str(d["scope"]),
          options: Support::Data.as_object(d["options"])
        )
      end
    end
  end
end
