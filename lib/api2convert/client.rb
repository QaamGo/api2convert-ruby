# frozen_string_literal: true

module Api2Convert
  # The API2Convert client — convert, compress and transform files with one call.
  #
  # {#convert} hides the multi-step job lifecycle (create -> upload -> start ->
  # poll -> download). For full control, use {#jobs} and the other resources.
  #
  # Quick start:
  #
  #   client = Api2Convert::Client.new("YOUR_API_KEY")
  #   client.convert("invoice.docx", "pdf").save("invoice.pdf")
  class Client
    # Matches a source that is a public URL (sent as a `remote` input) rather than
    # a local path. Anchored and linear — ReDoS-safe against a pathological input.
    URL_RE = %r{\Ahttps?://}i

    # Build the client. +api_key+ falls back to the `API2CONVERT_API_KEY`
    # environment variable when empty.
    #
    # Options: +base_url+, +timeout+, +max_retries+, +poll_interval+,
    # +poll_max_interval+, +poll_timeout+. For testing, inject +http_sender+ (an
    # object responding to `call(request)`), +sleeper+ (a proc) and +rng+ (a proc).
    def initialize(api_key = "", base_url: nil, timeout: nil, max_retries: nil,
                   poll_interval: nil, poll_max_interval: nil, poll_timeout: nil,
                   http_sender: nil, sleeper: nil, rng: nil)
      api_key = api_key.to_s
      api_key = ENV["API2CONVERT_API_KEY"].to_s if api_key.empty?
      if api_key.empty?
        raise ArgumentError,
              "No API key provided. Pass it to the constructor or set the " \
              "API2CONVERT_API_KEY environment variable."
      end

      config = Config.create(
        api_key,
        base_url: base_url, timeout: timeout, max_retries: max_retries,
        poll_interval: poll_interval, poll_max_interval: poll_max_interval,
        poll_timeout: poll_timeout
      )
      sender = http_sender || Http::NetHttpSender.new(timeout: config.timeout)
      @transport = Http::Transport.new(sender, config, sleeper: sleeper, rng: rng)

      uploader = Upload::FileUploader.new(@transport)
      @jobs = Resource::Jobs.new(@transport, uploader)
      @conversions = Resource::Conversions.new(@transport)
      @presets = Resource::Presets.new(@transport)
      @stats = Resource::Stats.new(@transport)
      @contracts = Resource::Contracts.new(@transport)
    end

    # Convert a file and wait for the result.
    #
    # Hand it a local path, a public URL, or an open IO, name the target format,
    # and get back a result you can `save`. +options+ are the target-specific
    # conversion options (discover them via {#options}). A +download_password+ is
    # remembered and applied automatically on download.
    #
    # @return [Result::ConversionResult]
    # A {Model::CloudInput} imports the source straight from customer storage (a
    # started job, like a remote URL). Pass +output_targets+ (a list of
    # {Model::OutputTarget}) to deliver the output(s) to customer storage instead
    # of producing a downloadable file — the job then completes with **no** local
    # output and the returned result is not downloaded (calling `output`/`save`
    # on it would have nothing to fetch). Output targets are attached to the
    # conversion's `output_target` and never merged into +options+.
    def convert(source, to, options = nil, category: nil, timeout: nil,
                output_index: nil, filename: nil, download_password: nil,
                output_targets: nil)
      job = start_conversion(source, to, options, category, nil, filename,
                             download_password, output_targets)
      done = @jobs.wait(job.id, timeout)
      Result::ConversionResult.new(done, @transport, output_index.nil? ? 0 : output_index, download_password)
    end

    # Start a conversion without waiting.
    #
    # Pass a +callback+ URL to be notified (sets `notify_status`), or poll later
    # with `client.jobs.get(job.id)` / `client.jobs.wait(job.id)`.
    #
    # @return [Model::Job]
    def convert_async(source, to, options = nil, callback: nil, category: nil,
                      filename: nil, download_password: nil, output_targets: nil)
      start_conversion(source, to, options, category, callback, filename,
                       download_password, output_targets)
    end

    # A {Result::FileDownload} for an output file. A +download_password+ is
    # remembered and sent automatically on download (overridable per call).
    def download(output, download_password = nil)
      Result::FileDownload.new(@transport, output, download_password)
    end

    # Discover the valid options (type / enum / default / range) for a target.
    def options(target, category = nil)
      @conversions.options(target, category)
    end

    attr_reader :jobs, :conversions, :presets, :stats, :contracts

    # Webhook verifier — usable without a configured client.
    def self.webhooks
      Webhook::Verifier.new
    end

    # No persistent connection is held (the transport opens per request), so this
    # is a no-op provided for symmetry with the sibling SDKs.
    def close
      nil
    end

    # Redacted representation. The default `#inspect` would recurse into the
    # transport and its config and dump the API key in cleartext, so it is
    # overridden to surface only the (non-secret) base URL.
    def inspect
      "#<#{self.class.name} base_url=#{@transport.config.base_url.inspect}>"
    end

    def to_s
      inspect
    end

    private

    def start_conversion(source, to, options, category, callback, filename,
                         download_password, output_targets = nil)
      conversion = { "target" => to }
      conversion["category"] = category unless category.nil?
      conversion["options"] = options if !options.nil? && !options.empty?
      # Cloud delivery targets attach to the conversion's `output_target` — never
      # merged into the options map.
      unless output_targets.nil? || output_targets.empty?
        conversion["output_target"] = Array(output_targets).map(&:to_h)
      end

      payload = { "conversion" => [conversion] }
      unless callback.nil?
        payload["callback"] = callback
        payload["notify_status"] = true
      end
      payload["download_passwords"] = [download_password] unless download_password.nil?

      # A cloud input imports from customer storage — a started job with the
      # descriptor inline, exactly like a remote URL (never staged/uploaded).
      if source.is_a?(Model::CloudInput)
        payload["process"] = true
        payload["input"] = [source.to_h]
        return @jobs.create(payload)
      end

      if source.is_a?(String) && source =~ URL_RE
        payload["process"] = true
        payload["input"] = [{ "type" => "remote", "source" => source }]
        return @jobs.create(payload)
      end

      payload["process"] = false
      created = @jobs.create(payload)
      @jobs.upload(created, source, filename)
      @jobs.start(created.id)
    end
  end
end
