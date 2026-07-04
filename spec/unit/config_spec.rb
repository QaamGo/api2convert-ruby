# frozen_string_literal: true

RSpec.describe Api2Convert::Config do
  it "applies sensible defaults" do
    config = described_class.create("k")
    expect(config.base_url).to eq("https://api.api2convert.com/v2")
    expect(config.timeout).to eq(30)
    expect(config.max_retries).to eq(2)
    expect(config.poll_interval).to eq(1.0)
    expect(config.poll_max_interval).to eq(5.0)
    expect(config.poll_timeout).to eq(300)
  end

  it "strips a trailing slash from the base URL" do
    expect(described_class.create("k", base_url: "https://example.test/v2/").base_url)
      .to eq("https://example.test/v2")
  end

  it "floors the poll interval so it can never busy-loop" do
    config = described_class.create("k", poll_interval: 0)
    expect(config.poll_interval).to eq(Api2Convert::Config::MIN_POLL_INTERVAL)
  end

  it "keeps the max interval at least the interval" do
    config = described_class.create("k", poll_interval: 4.0, poll_max_interval: 1.0)
    expect(config.poll_max_interval).to eq(4.0)
  end

  it "caps the poll timeout so it can never poll unbounded" do
    config = described_class.create("k", poll_timeout: 10_000_000)
    expect(config.poll_timeout).to eq(Api2Convert::Config::MAX_POLL_TIMEOUT)
  end

  it "clamps negatives up to their floors" do
    config = described_class.create("k", timeout: -5, max_retries: -1, poll_timeout: -1)
    expect(config.timeout).to eq(1)
    expect(config.max_retries).to eq(0)
    expect(config.poll_timeout).to eq(0)
  end

  it "is frozen" do
    expect(described_class.create("k")).to be_frozen
  end
end
