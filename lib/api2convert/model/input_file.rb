# frozen_string_literal: true

module Api2Convert
  module Model
    # An input file attached to a job.
    class InputFile
      attr_reader :id, :type, :source, :status, :filename, :size, :content_type, :options

      def initialize(id: nil, type: "", source: nil, status: nil, filename: nil,
                     size: nil, content_type: nil, options: {})
        @id = id
        @type = type
        @source = source
        @status = status
        @filename = filename
        @size = size
        @content_type = content_type
        @options = options
        freeze
      end

      def self.from_hash(data)
        d = Support::Data.as_object(data)
        new(
          id: Support::Data.nullable_str(d["id"]),
          type: Support::Data.as_str(d["type"]),
          source: Support::Data.nullable_str(d["source"]),
          status: Support::Data.nullable_str(d["status"]),
          filename: Support::Data.nullable_str(d["filename"]),
          size: Support::Data.nullable_int(d["size"]),
          content_type: Support::Data.nullable_str(d["content_type"]),
          options: Support::Data.as_object(d["options"])
        )
      end
    end
  end
end
