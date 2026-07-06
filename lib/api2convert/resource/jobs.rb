# frozen_string_literal: true

module Api2Convert
  module Resource
    # Full control over the job lifecycle.
    #
    # Most users only need `client.convert`, which is built on top of these
    # methods. Reach for this resource for compound jobs, merges, presets, custom
    # polling or job chaining. Methods are thin: build the request, call the
    # transport, hydrate a model.
    class Jobs
      def initialize(transport, uploader)
        @transport = transport
        @uploader = uploader
      end

      # Create a job. Pass `{ "process" => false }` to stage it for uploads, then
      # call {#start} once inputs are attached. +idempotency_key+ makes the create
      # retry-safe (sent as the `Idempotency-Key` header).
      def create(payload, idempotency_key = nil)
        headers = idempotency_key.nil? ? nil : { "Idempotency-Key" => idempotency_key }
        Model::Job.from_hash(@transport.request("POST", "/jobs", payload, nil, headers))
      end

      def get(job_id)
        Model::Job.from_hash(@transport.request("GET", "/jobs/#{Support::Data.encode_segment(job_id)}"))
      end

      # List the current key's jobs (paginated, 50 per page).
      def list(status = nil, page = 1)
        query = { "page" => page.to_s }
        query["status"] = status unless status.nil?
        rows = @transport.request("GET", "/jobs", nil, query)
        hashes(rows).map { |row| Model::Job.from_hash(row) }
      end

      def update(job_id, payload)
        Model::Job.from_hash(
          @transport.request("PATCH", "/jobs/#{Support::Data.encode_segment(job_id)}", payload)
        )
      end

      # Start processing a staged job (`process => true`).
      def start(job_id)
        update(job_id, { "process" => true })
      end

      # Cancel a job (whether staged or processing).
      def cancel(job_id)
        @transport.request("DELETE", "/jobs/#{Support::Data.encode_segment(job_id)}")
        nil
      end

      # Attach an input by descriptor, e.g. a remote URL:
      # `add_input(job_id, { "type" => "remote", "source" => "https://..." })`.
      def add_input(job_id, descriptor)
        Model::InputFile.from_hash(
          @transport.request("POST", "/jobs/#{Support::Data.encode_segment(job_id)}/input", descriptor)
        )
      end

      # Upload a local file (path or IO) to the job's upload server.
      def upload(job, file, filename = nil)
        @uploader.upload(job, file, filename)
      end

      # Block until the job reaches a terminal status, polling with backoff.
      #
      # Raises {ConversionFailedError} on a failed/canceled job (unless
      # +throw_on_failure+ is false) and {ConversionTimeoutError} past the
      # deadline. The interval is floored and the total wait capped, so no
      # configuration can busy-loop or poll unbounded.
      def wait(job_id, timeout_seconds = nil, throw_on_failure = true)
        config = @transport.config
        # Clamp again here (Config.create already clamps) so a directly-built
        # Config or a per-call override can never busy-loop or poll unbounded.
        requested = timeout_seconds.nil? ? config.poll_timeout : timeout_seconds
        timeout = requested.clamp(0, Config::MAX_POLL_TIMEOUT)
        max_interval = [Config::MIN_POLL_INTERVAL, config.poll_max_interval].max
        interval = [Config::MIN_POLL_INTERVAL, config.poll_interval].max
        deadline = monotonic + timeout

        loop do
          job = get(job_id)

          raise ConversionFailedError.new(job) if (job.failed? || job.canceled?) && throw_on_failure
          return job if job.terminal?
          raise ConversionTimeoutError.new(job, timeout) if monotonic >= deadline

          @transport.pause(interval)
          interval = [max_interval, interval * 1.5].min
        end
      end

      # Outputs produced by the job (use {#get} or {#wait} first).
      def outputs(job_id)
        rows = @transport.request("GET", "/jobs/#{Support::Data.encode_segment(job_id)}/output")
        hashes(rows).map { |row| Model::OutputFile.from_hash(row) }
      end

      private

      def hashes(rows)
        Support::Data.as_list(rows).grep(Hash)
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
