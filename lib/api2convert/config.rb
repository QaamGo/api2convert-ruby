# frozen_string_literal: true

module Api2Convert
  # Immutable client configuration.
  #
  # Build via {Config.create}, which clamps every knob so a caller value can
  # neither busy-loop the poll (interval floor) nor poll unbounded (timeout
  # ceiling).
  class Config
    # Default API base URL — includes the `/v2` path segment, no trailing slash.
    DEFAULT_BASE_URL = "https://api.api2convert.com/v2"

    # Hard floor for the job-poll interval (seconds); prevents a busy-spin self-DDOS.
    MIN_POLL_INTERVAL = 0.5

    # Hard ceiling for the total job-poll timeout (4 hours); bounds an unbounded poll.
    MAX_POLL_TIMEOUT = 14_400

    attr_reader :api_key, :base_url, :timeout, :max_retries,
                :poll_interval, :poll_max_interval, :poll_timeout

    # The constructor does not clamp — use {create} (the single entry point the
    # client uses) so a caller value can never busy-loop or poll unbounded.
    def initialize(api_key:, base_url:, timeout:, max_retries:,
                   poll_interval:, poll_max_interval:, poll_timeout:)
      @api_key = api_key
      @base_url = base_url
      @timeout = timeout
      @max_retries = max_retries
      @poll_interval = poll_interval
      @poll_max_interval = poll_max_interval
      @poll_timeout = poll_timeout
      freeze
    end

    def self.create(api_key, base_url: nil, timeout: nil, max_retries: nil,
                    poll_interval: nil, poll_max_interval: nil, poll_timeout: nil)
      interval = [MIN_POLL_INTERVAL, (poll_interval.nil? ? 1.0 : poll_interval).to_f].max
      max_interval = [interval, (poll_max_interval.nil? ? 5.0 : poll_max_interval).to_f].max
      timeout_value = (poll_timeout.nil? ? 300 : poll_timeout).to_i.clamp(0, MAX_POLL_TIMEOUT)

      new(
        api_key: api_key,
        base_url: (base_url.nil? ? DEFAULT_BASE_URL : base_url).sub(%r{/+\z}, ""),
        timeout: [1, (timeout.nil? ? 30 : timeout).to_i].max,
        max_retries: [0, (max_retries.nil? ? 2 : max_retries).to_i].max,
        poll_interval: interval,
        poll_max_interval: max_interval,
        poll_timeout: timeout_value
      )
    end

    # Redacted representation — the API key is masked so it can never be printed
    # in cleartext by `p config`, a logger, or an object dumped in a backtrace.
    def inspect
      "#<#{self.class.name} api_key=#{Support::Secret.mask(@api_key)} " \
        "base_url=#{@base_url.inspect} timeout=#{@timeout} max_retries=#{@max_retries} " \
        "poll_interval=#{@poll_interval} poll_max_interval=#{@poll_max_interval} " \
        "poll_timeout=#{@poll_timeout}>"
    end

    def to_s
      inspect
    end
  end
end
