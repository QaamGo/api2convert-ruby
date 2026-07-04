# frozen_string_literal: true

require "stringio"

module Api2Convert
  module Upload
    # A read-only IO that concatenates a multipart preamble, the file body IO, and
    # the trailing boundary — so the body is streamed to the socket rather than
    # loaded into memory. `Net::HTTP#body_stream=` reads it via `#read(len)`.
    class MultipartStream
      # Build the streamed body for a single `file` field. Returns
      # `[stream, content_length]`; the caller sets `Content-Length` from the
      # length so `Net::HTTP` does not fall back to chunked encoding.
      #
      # +io+ must be positioned at the start and expose a byte {#size} (a File or
      # a StringIO both do — the uploader coerces anything else into a StringIO).
      def self.build(boundary, field, filename, io)
        disposition = %(form-data; name="#{escape(field)}"; filename="#{escape(filename)}")
        preamble = [
          "--#{boundary}",
          "Content-Disposition: #{disposition}",
          "Content-Type: application/octet-stream",
          "",
          ""
        ].join("\r\n").b
        epilogue = "\r\n--#{boundary}--\r\n".b

        body_size = io.size - (io.respond_to?(:pos) ? io.pos : 0)
        length = preamble.bytesize + body_size + epilogue.bytesize
        [new(preamble, io, epilogue), length]
      end

      # Strip quotes and CR/LF from a header parameter so it can't break out of
      # the multipart header (header-injection defense).
      def self.escape(value)
        value.to_s.gsub('"', "%22").gsub(/[\r\n]/, "")
      end

      def initialize(preamble, io, epilogue)
        @parts = [StringIO.new(preamble), io, StringIO.new(epilogue)]
        @index = 0
      end

      # Read up to +length+ bytes across the parts. With no length, reads all that
      # remains. Returns nil at end of stream (the contract `Net::HTTP` expects).
      def read(length = nil, outbuf = nil)
        buffer = outbuf || "".b
        buffer.clear

        if length.nil?
          while @index < @parts.length
            chunk = @parts[@index].read
            buffer << chunk unless chunk.nil?
            @index += 1
          end
          return buffer
        end

        while buffer.bytesize < length && @index < @parts.length
          chunk = @parts[@index].read(length - buffer.bytesize)
          if chunk.nil?
            @index += 1
          else
            buffer << chunk
          end
        end

        return nil if buffer.empty? && @index >= @parts.length

        buffer
      end
    end
  end
end
