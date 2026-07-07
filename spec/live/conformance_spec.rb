# frozen_string_literal: true

require "base64"
require "tmpdir"

# Live conformance suite — the canonical, cross-SDK set of scenarios that
# exercises the real API2Convert API end to end. Every example is written to read
# like idiomatic usage, so this file doubles as an executable tour of the SDK:
# build a client, convert, discover the catalog, drive the job lifecycle by hand,
# and handle the typed errors.
#
# Because these hit the real API and consume quota, the whole suite is gated on a
# key: each example skips (passes) unless API2CONVERT_API_KEY is set. Point at a
# different host (e.g. a beta environment) with API2CONVERT_BASE_URL. Never commit
# a real key — it is read only from the environment.
#
#   API2CONVERT_API_KEY=<key> bundle exec rake spec:live
#
# The seven scenarios mirror the shared spec implemented by every api2convert SDK
# (php, python, java, go, nodejs, dotnet, ruby, rust):
#
#   1. convert_remote_url_to_png            — one-call convert of a URL
#   2. upload_local_file_and_convert        — multipart upload of a local file
#   3. convert_with_options                 — apply target-specific options
#   4. discover_conversion_catalog          — list conversions / option schema
#   5. manual_job_lifecycle_and_inspection  — create -> input -> start -> wait
#   6. invalid_target_is_a_typed_error      — validation error handling
#   7. authentication_error_leaks_no_secret — auth error, no key leak
RSpec.describe "live conformance", :live do
  # A small, stable public image used as a remote input everywhere.
  REMOTE_JPG = "https://example-files.online-convert.com/raster%20image/jpg/example_small.jpg"

  # A minimal valid 1x1 PNG, written to disk to exercise the real multipart upload
  # handshake (remote-URL inputs skip upload entirely). Kept inline so the suite
  # needs no binary fixture.
  ONE_PX_PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
  )

  before do
    skip "live tests require API2CONVERT_API_KEY" if ENV["API2CONVERT_API_KEY"].to_s.empty?
  end

  # The idiomatic construction: the API key falls back to API2CONVERT_API_KEY, and
  # we honor API2CONVERT_BASE_URL so the same suite can target prod or a beta host.
  def client(api_key = "")
    base_url = ENV.fetch("API2CONVERT_BASE_URL", nil)
    if base_url.nil? || base_url.empty?
      Api2Convert::Client.new(api_key)
    else
      Api2Convert::Client.new(api_key, base_url: base_url)
    end
  end

  # 1. One-call convert of a remote URL.
  #
  # The simplest usage: hand `convert` a URL and a target format. The SDK creates
  # a server-side-fetch job, polls it to completion, and hands back a result you
  # can save straight to disk.
  it "converts a remote URL to png" do
    result = client.convert(REMOTE_JPG, "png")

    expect(result.job).to be_completed
    Dir.mktmpdir("a2c-live-remote") do |dir|
      path = result.save(dir) # a directory keeps the API filename
      expect(File.size(path)).to be > 0
    end
  end

  # 2. Upload and convert a local file.
  #
  # For a local path (or an open IO), the SDK stages the job, streams the file to
  # the per-job upload server (authenticated with the job's token, never your
  # account key), starts it, polls, and downloads.
  it "uploads a local file and converts it to jpg" do
    Dir.mktmpdir("a2c-live-upload") do |dir|
      source = File.join(dir, "pixel.png")
      File.binwrite(source, ONE_PX_PNG)

      result = client.convert(source, "jpg")

      expect(result.job).to be_completed
      bytes = result.contents
      expect(bytes.bytesize).to be > 0
      # A JPEG starts with the SOI marker 0xFF 0xD8.
      expect(bytes.byteslice(0, 2).bytes).to eq([0xFF, 0xD8])
    end
  end

  # 3. Apply conversion options.
  #
  # Pass target-specific options as a plain hash. Discover the valid keys for a
  # target with `client.options` (see the next scenario); here we re-encode at a
  # lower JPEG quality. Add e.g. "width" => 64, "height" => 64 to resize.
  it "converts with target-specific options" do
    result = client.convert(REMOTE_JPG, "jpg", { "quality" => 50 })

    expect(result.job).to be_completed
    expect(result.contents.bytesize).to be > 0
  end

  # 4. Discover the conversion catalog.
  #
  # `conversions.list` and `options` describe what the API can do — which targets
  # exist and which options each accepts. Neither consumes conversion quota, so
  # they are cheap to call before building a request.
  it "discovers the conversion catalog" do
    api = client

    # Which conversions target `jpg`?
    conversions = api.conversions.list(nil, "jpg")
    expect(conversions).not_to be_empty

    # The option schema (type / enum / default / range per option) for a target.
    # `category` disambiguates an ambiguous target — pass "image" for png.
    expect { api.options("png", "image") }.not_to raise_error
  end

  # 5. Drive the full job lifecycle by hand.
  #
  # `convert` is built from these primitives. Driving them yourself unlocks
  # compound/merge jobs, custom inputs and step-by-step inspection: create a
  # staged job, attach an input, start it, wait for completion, then inspect the
  # job's status and output metadata.
  it "drives the job lifecycle manually and inspects the outputs" do
    jobs = client.jobs

    # Stage a job (process: false) so we can attach inputs before starting.
    job = jobs.create({ "process" => false, "conversion" => [{ "target" => "png" }] })
    expect(job.id).not_to be_empty

    # Attach a remote input, then start processing.
    jobs.add_input(job.id, { "type" => "remote", "source" => REMOTE_JPG })
    jobs.start(job.id)

    # Poll to a terminal status (raises on a failed job by default).
    finished = jobs.wait(job.id)
    expect(finished).to be_completed

    # Inspect the outputs — both from the finished job and via the outputs API.
    expect(finished.output).not_to be_empty
    expect(jobs.outputs(job.id).length).to eq(finished.output.length)
    expect(finished.output.first.uri).not_to be_empty
  end

  # 6. Validation error on an unknown target.
  #
  # The API rejects an unknown target — either synchronously at create time
  # (ValidationError) or as a failed job (ConversionFailedError). Both are typed
  # errors you can rescue.
  it "raises a typed error for an invalid target" do
    expect { client.convert(REMOTE_JPG, "this-is-not-a-real-target") }
      .to raise_error(an_instance_of(Api2Convert::ValidationError)
        .or(an_instance_of(Api2Convert::ConversionFailedError)))
  end

  # 7. Authentication error, with no secret leak.
  #
  # A bad key produces a typed AuthenticationError carrying the HTTP status.
  # Crucially, the SDK never puts a credential into an error message — we assert
  # the bogus key does not appear in the rendered error.
  it "surfaces a typed authentication error without leaking the key" do
    bogus_key = "a2c-invalid-key-for-testing"
    bad_client = client(bogus_key)

    begin
      bad_client.jobs.list
      raise "a bad key must not authenticate"
    rescue Api2Convert::AuthenticationError => e
      expect([401, 403]).to include(e.status_code)
      expect(e.message).not_to include(bogus_key)
    end
  end
end
