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
    def convert(source, to, options = nil, category: nil, timeout: nil,
                output_index: nil, filename: nil, download_password: nil)
      job = start_conversion(source, to, options, category, nil, filename, download_password)
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
                      filename: nil, download_password: nil)
      start_conversion(source, to, options, category, callback, filename, download_password)
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

    private

    def start_conversion(source, to, options, category, callback, filename, download_password)
      conversion = { "target" => to }
      conversion["category"] = category unless category.nil?
      conversion["options"] = options if !options.nil? && !options.empty?

      payload = { "conversion" => [conversion] }
      unless callback.nil?
        payload["callback"] = callback
        payload["notify_status"] = true
      end
      payload["download_passwords"] = [download_password] unless download_password.nil?

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
