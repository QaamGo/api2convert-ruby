# frozen_string_literal: true

module Api2Convert
  module Model
    # A conversion job — the central API2Convert resource.
    #
    # {#server} and {#token} are needed to upload local files; {#output} holds the
    # produced files once {#completed?}. {#raw} keeps the full decoded response for
    # fields not surfaced as typed attributes.
    class Job
      attr_reader :id, :status, :token, :server, :callback,
                  :conversion, :input, :output, :errors, :warnings, :raw

      def initialize(id:, status:, token:, server:, callback:,
                     conversion:, input:, output:, errors:, warnings:, raw:)
        @id = id
        @status = status
        @token = token
        @server = server
        @callback = callback
        @conversion = conversion
        @input = input
        @output = output
        @errors = errors
        @warnings = warnings
        @raw = raw
        freeze
      end

      def self.from_hash(data)
        d = Support::Data.as_object(data)
        new(
          id: Support::Data.as_str(d["id"]),
          status: Status.from_hash(d["status"]),
          token: Support::Data.nullable_str(d["token"]),
          server: Support::Data.nullable_str(d["server"]),
          callback: Support::Data.nullable_str(d["callback"]),
          conversion: Support::Data.map_objects(d["conversion"]) { |x| Conversion.from_hash(x) },
          input: Support::Data.map_objects(d["input"]) { |x| InputFile.from_hash(x) },
          output: Support::Data.map_objects(d["output"]) { |x| OutputFile.from_hash(x) },
          errors: Support::Data.map_objects(d["errors"]) { |x| JobMessage.from_hash(x) },
          warnings: Support::Data.map_objects(d["warnings"]) { |x| JobMessage.from_hash(x) },
          raw: d
        )
      end

      def completed?
        @status.code == JobStatus::COMPLETED
      end

      def failed?
        @status.code == JobStatus::FAILED
      end

      # The job was canceled server-side — terminal, and produced no output.
      def canceled?
        @status.code == JobStatus::CANCELED
      end

      # Finished (completed, failed or canceled) and will not change further.
      def terminal?
        JobStatus.terminal?(@status.code)
      end
    end
  end
end
