# frozen_string_literal: true

module Api2Convert
  module Model
    # A produced output file.
    #
    # {#uri} is a self-contained download URL (no auth), valid for a limited time
    # (24h by default).
    class OutputFile
      attr_reader :id, :uri, :filename, :size, :status, :content_type, :checksum, :metadata

      def initialize(id: nil, uri: "", filename: nil, size: nil, status: nil,
                     content_type: nil, checksum: nil, metadata: {})
        @id = id
        @uri = uri
        @filename = filename
        @size = size
        @status = status
        @content_type = content_type
        @checksum = checksum
        @metadata = metadata
        freeze
      end

      def self.from_hash(data)
        d = Support::Data.as_object(data)
        new(
          id: Support::Data.nullable_str(d["id"]),
          uri: Support::Data.as_str(d["uri"]),
          filename: Support::Data.nullable_str(d["filename"]),
          size: Support::Data.nullable_int(d["size"]),
          status: Support::Data.nullable_str(d["status"]),
          content_type: Support::Data.nullable_str(d["content_type"]),
          checksum: Support::Data.nullable_str(d["checksum"]),
          metadata: Support::Data.as_object(d["metadata"])
        )
      end
    end
  end
end
