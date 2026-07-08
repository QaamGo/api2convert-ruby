# frozen_string_literal: true

require "base64"
require "tmpdir"

# Live conformance suite — the canonical, cross-SDK set of scenarios that
# exercises the real API2Convert API end to end. Each scenario mirrors one
# runnable example in `examples/` (same operation, plus assertions), so this file
# doubles as an executable tour of the documented guides: quickstart, converting
# files, uploading, the job lifecycle, watermarks, thumbnails, compression,
# archives, hashes, asset extraction, analysis, comparison, website capture,
# audio/image operations, webhooks, presets, statistics, rate limits and auth.
#
# Because these hit the real API and consume quota, the whole suite is gated on a
# key: each example skips (passes) unless API2CONVERT_API_KEY is set. Point at a
# different host (e.g. a beta environment) with API2CONVERT_BASE_URL. Never commit
# a real key — it is read only from the environment.
#
#   API2CONVERT_API_KEY=<key> bundle exec rake spec:live
#
# The 20 positive scenarios map 1:1 to the documented example catalog; the two
# negative scenarios (invalid target, bad key) round out the typed-error contract
# shared by every api2convert SDK (php, python, java, go, nodejs, dotnet, ruby,
# rust).
RSpec.describe "live conformance", :live do
  # Remote fixtures — the public online-convert example files.
  REMOTE_PDF = "https://example-files.online-convert.com/document/pdf/example.pdf"
  REMOTE_PNG = "https://example-files.online-convert.com/raster%20image/png/example.png"
  REMOTE_JPG = "https://example-files.online-convert.com/raster%20image/jpg/example.jpg"
  REMOTE_JPG_SMALL = "https://example-files.online-convert.com/raster%20image/jpg/example_small.jpg"
  REMOTE_WAV = "https://example-files.online-convert.com/audio/wav/example.wav"
  REMOTE_DOCX = "https://example-files.online-convert.com/document/docx/example.docx"
  REMOTE_ZIP = "https://example-files.online-convert.com/archive/zip/example.zip"

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

  # 1. quickstart — convert a remote URL, fetch the job, download the output.
  it "runs the quickstart: convert, get the job, download" do
    api = client
    result = api.convert(REMOTE_JPG, "png", category: "image")
    expect(result.job).to be_completed

    fetched = api.jobs.get(result.job.id)
    expect(fetched.id).to eq(result.job.id)

    Dir.mktmpdir("a2c-quickstart") do |dir|
      path = result.save(dir)
      expect(File.size(path)).to be > 0
    end
  end

  # 2. convert-files — browse the catalog (all, then filtered), then convert.
  it "lists the conversions catalog and converts a jpg to png" do
    api = client

    expect(api.conversions.list).not_to be_empty
    expect(api.conversions.list("image", "png")).not_to be_empty

    result = api.convert(REMOTE_JPG, "png", category: "image")
    expect(result.job).to be_completed
    expect(result.contents.bytesize).to be > 0
  end

  # 3. uploading-files — one-call upload + convert of a local file.
  it "uploads a local file and converts it to png" do
    Dir.mktmpdir("a2c-upload") do |dir|
      source = File.join(dir, "pixel.png")
      File.binwrite(source, ONE_PX_PNG)

      result = client.convert(source, "png", category: "image")
      expect(result.job).to be_completed
      expect(result.contents.bytesize).to be > 0
    end
  end

  # 4. job-lifecycle — create (staged) -> add input -> start -> wait -> outputs.
  it "drives the job lifecycle manually" do
    jobs = client.jobs

    job = jobs.create({ "process" => false, "conversion" => [{ "category" => "image", "target" => "png" }] })
    expect(job.id).not_to be_empty

    jobs.add_input(job.id, { "type" => "remote", "source" => REMOTE_JPG })
    jobs.start(job.id)

    done = jobs.wait(job.id)
    expect(done).to be_completed
    expect(jobs.outputs(job.id)).not_to be_empty
  end

  # 5. add-watermark — stamp a PDF with an image (two remote inputs).
  it "adds a watermark to a pdf" do
    jobs = client.jobs
    job = jobs.create(
      {
        "process" => true,
        "input" => [
          { "type" => "remote", "source" => REMOTE_PDF },
          { "type" => "remote", "source" => REMOTE_PNG }
        ],
        "conversion" => [
          {
            "category" => "document", "target" => "pdf",
            "options" => { "stamp" => true, "alignment" => "center" }
          }
        ]
      }
    )
    expect(jobs.wait(job.id)).to be_completed
    expect(jobs.outputs(job.id)).not_to be_empty
  end

  # 6. create-thumbnails — render the first PDF page as a PNG thumbnail.
  it "creates a thumbnail of a pdf" do
    result = client.convert(
      REMOTE_PDF, "thumbnail",
      { "thumbnail_target" => "png", "width" => 300, "pages" => "first", "dpi" => 150 },
      category: "operation"
    )
    expect(result.job).to be_completed
    expect(result.contents.bytesize).to be > 0
  end

  # 7. compress-files — compress an image via the compress operation.
  it "compresses an image" do
    result = client.convert(REMOTE_JPG, "compress", { "compression_level" => "high" }, category: "operation")
    expect(result.job).to be_completed
    expect(result.contents.bytesize).to be > 0
  end

  # 8. create-archives — bundle two remote files into a ZIP.
  it "creates a zip archive from remote inputs" do
    jobs = client.jobs
    job = jobs.create(
      {
        "process" => true,
        "input" => [
          { "type" => "remote", "source" => REMOTE_PDF },
          { "type" => "remote", "source" => REMOTE_PNG }
        ],
        "conversion" => [{ "category" => "archive", "target" => "zip" }]
      }
    )
    expect(jobs.wait(job.id)).to be_completed
    expect(jobs.outputs(job.id)).not_to be_empty
  end

  # 9. create-hashes — compute a file's SHA-256 checksum.
  it "computes a sha256 hash" do
    result = client.convert(REMOTE_ZIP, "sha256", category: "hash")
    expect(result.job).to be_completed
    expect(result.contents.bytesize).to be > 0
  end

  # 10. extract-assets — extract embedded assets from a document.
  it "extracts assets from a document" do
    result = client.convert(REMOTE_DOCX, "extract-assets", category: "operation")
    expect(result.job).to be_completed
    expect(result.outputs).not_to be_empty
  end

  # 11. file-analysis — extract metadata as JSON.
  it "analyzes a file's metadata as json" do
    result = client.convert(REMOTE_JPG, "json", category: "metadata")
    expect(result.job).to be_completed
    expect(result.contents.bytesize).to be > 0
  end

  # 12. compare-files — diff two images with compare-image.
  it "compares two images" do
    jobs = client.jobs
    job = jobs.create(
      {
        "process" => true,
        "input" => [
          { "type" => "remote", "source" => REMOTE_JPG_SMALL },
          { "type" => "remote", "source" => REMOTE_JPG }
        ],
        "conversion" => [
          {
            "category" => "operation", "target" => "compare-image",
            "options" => { "method" => "ssim", "threshold" => 5, "diff_color" => "red" }
          }
        ]
      }
    )
    expect(jobs.wait(job.id)).to be_completed
  end

  # 13. capture-website — screenshot a page with the screenshot engine.
  it "captures a screenshot of a website" do
    jobs = client.jobs
    job = jobs.create(
      {
        "process" => true,
        "input" => [
          {
            "type" => "remote", "source" => "https://www.online-convert.com", "engine" => "screenshot",
            "options" => { "screen_width" => 1280, "screen_height" => 1024, "device_scale_factor" => 1 }
          }
        ],
        "conversion" => [{ "category" => "image", "target" => "png" }]
      }
    )
    expect(jobs.wait(job.id)).to be_completed
    expect(jobs.outputs(job.id)).not_to be_empty
  end

  # 14. audio-operations — re-encode a WAV to AAC.
  it "re-encodes audio to aac" do
    result = client.convert(
      REMOTE_WAV, "aac",
      { "audio_codec" => "aac", "audio_bitrate" => 192, "channels" => "stereo", "frequency" => 44_100 },
      category: "audio"
    )
    expect(result.job).to be_completed
    expect(result.contents.bytesize).to be > 0
  end

  # 15. image-operations — resize an image.
  it "resizes an image" do
    result = client.convert(
      REMOTE_JPG, "resize-image",
      { "width" => 800, "height" => 600, "resize_by" => "px", "resize_handling" => "keep_aspect_ratio_crop" },
      category: "operation"
    )
    expect(result.job).to be_completed
    expect(result.contents.bytesize).to be > 0
  end

  # 16. webhooks — convert_async with a callback returns a started job.
  it "starts an async job with a webhook callback" do
    job = client.convert_async(
      REMOTE_DOCX, "pdf",
      callback: "https://your-app.example.com/api2convert/webhook", category: "document"
    )
    expect(job.id).not_to be_empty
  end

  # 17. presets — list saved presets (may be empty).
  it "lists presets" do
    presets = client.presets.list(category: "video", target: "mp4")
    expect(presets).to be_an(Array)
  end

  # 18. statistics — read usage for a recent month.
  it "reads monthly statistics" do
    expect { client.stats.month("2026-06") }.not_to raise_error
  end

  # 19. rate-limits — read the account's contracts.
  it "reads the account contracts" do
    expect { client.contracts.get }.not_to raise_error
  end

  # 20. authentication — a valid key lists jobs.
  it "authenticates and lists jobs" do
    expect(client.jobs.list).to be_an(Array)
  end

  # Negative 1. Validation error on an unknown target.
  #
  # The API rejects an unknown target — either synchronously at create time
  # (ValidationError) or as a failed job (ConversionFailedError). Both are typed.
  it "raises a typed error for an invalid target" do
    expect { client.convert(REMOTE_JPG, "this-is-not-a-real-target") }
      .to raise_error(an_instance_of(Api2Convert::ValidationError)
        .or(an_instance_of(Api2Convert::ConversionFailedError)))
  end

  # Negative 2. Authentication error, with no secret leak.
  #
  # A bad key produces a typed AuthenticationError carrying the HTTP status. The
  # SDK never puts a credential into an error message — assert the bogus key does
  # not appear in the rendered error.
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
