# frozen_string_literal: true

require "stringio"
require "securerandom"

module Api2Convert
  module Upload
    # Uploads a local file to a job's per-job upload server.
    #
    # This step is intentionally hand-written — it is NOT described by the OpenAPI
    # spec. It posts a `multipart/form-data` body (field `file`) to
    # `{job.server}/upload-file/{job.id}` and authenticates with the per-job
    # `X-Oc-Token` header — never the account API key. The body is streamed, so
    # large files are not read into memory. Internal.
    class FileUploader
      def initialize(transport)
        @transport = transport
      end

      # @param job [Model::Job] a staged job (created with `process: false`).
      # @param file [String, Pathname, IO] a path, or an IO/StringIO of bytes.
      # @return [Model::InputFile]
      def upload(job, file, filename = nil)
        if job.server.nil? || job.server.empty? || job.token.nil?
          raise Api2Convert::Error,
                "Cannot upload: the job has no upload server/token. " \
                "Create the job with process=false and upload before starting it."
        end

        io, resolved_name, opened = resolve(file, filename)
        seekable = io.respond_to?(:rewind)
        url = "#{job.server.sub(%r{/+\z}, "")}/upload-file/#{job.id}"
        token = job.token
        boundary = "----Api2Convert#{SecureRandom.hex(16)}"

        build = lambda do
          io.rewind if seekable
          body_stream, length = MultipartStream.build(boundary, "file", resolved_name, io)
          @transport.build_request(
            "POST", url,
            headers: {
              "X-Oc-Token" => token,
              "Content-Type" => "multipart/form-data; boundary=#{boundary}"
            },
            body_stream: body_stream,
            content_length: length
          )
        end

        begin
          response = @transport.send_request(build, replayable: seekable)
          Model::InputFile.from_hash(@transport.interpret(response))
        ensure
          opened&.close
        end
      end

      private

      # Returns `[io, filename, opened]` where +opened+ is the handle to close
      # afterwards (nil when the caller owns the IO). A path/Pathname is opened in
      # binary mode; any other IO without a known byte size is buffered so the
      # multipart Content-Length can be computed.
      def resolve(file, filename)
        if file.is_a?(String) || file.respond_to?(:to_path)
          raw_path = file.respond_to?(:to_path) ? file.to_path : file
          path = File.realpath(raw_path)
          raise Api2Convert::Error, "Input file not found: #{file}" unless File.file?(path)

          # Opened without a block on purpose: the handle is streamed by the
          # transport and closed in upload's ensure clause.
          handle = File.open(path, "rb") # rubocop:disable Style/FileOpen
          # Mirror the null-coalesce: only nil falls back to the default, so an
          # explicit "" filename is preserved as given.
          name = filename.nil? ? File.basename(path) : filename
          return [handle, name, handle]
        end

        io = file
        io = StringIO.new(io.read) unless io.respond_to?(:size) && io.respond_to?(:rewind)
        [io, filename.nil? ? "file" : filename, nil]
      rescue Errno::ENOENT
        raise Api2Convert::Error, "Input file not found: #{file}"
      end
    end
  end
end
