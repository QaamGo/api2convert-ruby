# frozen_string_literal: true

module Api2Convert
  module Resource
    # Saved conversion presets (reusable named target + options).
    class Presets
      def initialize(transport)
        @transport = transport
      end

      def list(category: nil, target: nil, filter: nil)
        query = {}
        query["category"] = category unless category.nil?
        query["target"] = target unless target.nil?
        query["filter"] = filter unless filter.nil?
        rows = @transport.request("GET", "/presets", nil, query)
        Support::Data.as_list(rows).grep(Hash).map { |row| Model::Preset.from_hash(row) }
      end

      # Create a preset from `{ name, target, options, scope?, category? }`.
      def create(payload)
        Model::Preset.from_hash(@transport.request("POST", "/presets", payload))
      end

      def get(preset_id)
        Model::Preset.from_hash(
          @transport.request("GET", "/presets/#{Support::Data.encode_segment(preset_id)}")
        )
      end

      def update(preset_id, payload)
        Model::Preset.from_hash(
          @transport.request("PATCH", "/presets/#{Support::Data.encode_segment(preset_id)}", payload)
        )
      end

      def delete(preset_id)
        @transport.request("DELETE", "/presets/#{Support::Data.encode_segment(preset_id)}")
        nil
      end
    end
  end
end
