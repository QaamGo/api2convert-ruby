# frozen_string_literal: true

require "base64"
require "stringio"
require "tmpdir"

# End-to-end conformance against the real API. Skipped unless
# API2CONVERT_API_KEY is set (supply the behat key). Optionally point at another
# host with API2CONVERT_BASE_URL. Mirrors the sibling SDKs' live conformance test.
#
#   API2CONVERT_API_KEY=<behat key> rake spec:live
RSpec.describe "live conformance", :live do
  REMOTE_JPG = "https://example-files.online-convert.com/raster%20image/jpg/example.jpg"

  # A 1x1 PNG, so the upload path can be exercised without shipping a binary fixture.
  TINY_PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
  )

  before do
    skip "live tests require API2CONVERT_API_KEY" if ENV["API2CONVERT_API_KEY"].to_s.empty?
  end

  def client
    base_url = ENV.fetch("API2CONVERT_BASE_URL", nil)
    if base_url.nil? || base_url.empty?
      Api2Convert::Client.new
    else
      Api2Convert::Client.new(base_url: base_url)
    end
  end

  it "converts a remote image to png and downloads it" do
    result = client.convert(REMOTE_JPG, "png")
    expect(result.job).to be_completed
    Dir.mktmpdir do |dir|
      path = result.save(dir)
      expect(File.size(path)).to be > 0
    end
  end

  it "converts an uploaded local file to jpg and downloads it" do
    Dir.mktmpdir do |dir|
      source = File.join(dir, "pixel.png")
      File.binwrite(source, TINY_PNG)
      result = client.convert(source, "jpg")
      expect(result.job).to be_completed
      expect(result.contents.bytesize).to be > 0
    end
  end

  it "raises ValidationError for an unknown target" do
    expect { client.convert(REMOTE_JPG, "this-is-not-a-real-target") }
      .to raise_error(Api2Convert::ValidationError)
  end

  it "discovers the option schema for a target" do
    expect(client.options("jpg")).not_to be_empty
  end
end
