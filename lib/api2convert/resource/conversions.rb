# frozen_string_literal: true

module Api2Convert
  module Resource
    # The conversions catalog (`GET /conversions`).
    #
    # The source of truth for which targets exist and which options each accepts.
    class Conversions
      def initialize(transport)
        @transport = transport
      end

      # List supported conversions, optionally filtered by category/target. Each
      # entry: `{ id, category, target, options }`.
      def list(category = nil, target = nil, page = 1)
        query = { "page" => page.to_s }
        query["category"] = category unless category.nil?
        query["target"] = target unless target.nil?
        rows = @transport.request("GET", "/conversions", nil, query)
        Support::Data.as_list(rows).grep(Hash)
      end

      # The option schema (type / enum / default / range) for a single target.
      # +category+ is optional — pass it only to disambiguate an ambiguous target.
      def options(target, category = nil)
        rows = list(category, target)
        first = rows.first || {}
        opts = first["options"]
        opts.is_a?(Hash) ? opts : {}
      end
    end
  end
end
