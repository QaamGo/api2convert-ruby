# API2Convert Ruby SDK

[![CI](https://github.com/QaamGo/api2convert-ruby/actions/workflows/ci.yml/badge.svg)](https://github.com/QaamGo/api2convert-ruby/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/api2convert)](https://rubygems.org/gems/api2convert)
![Ruby](https://img.shields.io/badge/ruby-%E2%89%A5%203.1-red)
![License](https://img.shields.io/badge/license-MIT-green)

Official Ruby SDK for the [API2Convert](https://www.api2convert.com) file-conversion API.
Convert, compress and transform images, documents, audio, video, ebooks, archives and CAD —
and run operations like OCR, merge, thumbnail and website capture — in one line of code.

Zero runtime dependencies: built entirely on the Ruby standard library.

## Installation

```ruby
# Gemfile
gem "api2convert"
```

```console
$ bundle install
# or
$ gem install api2convert
```

Requires Ruby 3.1+.

## Quick start

```ruby
require "api2convert"

client = Api2Convert::Client.new("YOUR_API_KEY")

# 1) From a local file
client.convert("photo.png", "jpg").save("photo.jpg")

# 2) From a URL
client.convert("https://example.com/photo.png", "jpg").save("photo.jpg")

# 3) With conversion options (discover them via client.options)
client.convert("photo.png", "jpg", { "quality" => 85, "width" => 1280, "height" => 720 })
      .save("out/")
```

The API key falls back to the `API2CONVERT_API_KEY` environment variable when you
construct the client without one.

## Working with the result

```ruby
result = client.convert("report.docx", "pdf")

result.save("report.pdf")   # stream to a file path
result.save("downloads/")   # ...or a directory (keeps the API filename)
bytes = result.contents     # the raw bytes
url   = result.url          # just the (self-contained) download URL
```

## Password-protected output

```ruby
result = client.convert("statement.docx", "pdf", download_password: "hunter2")
result.save("statement.pdf")   # the password is remembered and applied automatically

# Or when you hold an OutputFile from elsewhere:
client.download(output, "hunter2").save("out/")
```

## Async + webhooks

```ruby
job = client.convert_async("movie.mov", "mp4",
                           callback: "https://your-app.example.com/webhooks/api2convert")

# In your webhook handler (Rack-style):
payload   = request.body.read
signature = request.get_header("HTTP_X_OC_SIGNATURE")

begin
  event = Api2Convert.webhooks.construct_event(payload, signature, "YOUR_WEBHOOK_SECRET")
  job   = event.job
  # react to job.status.code
rescue Api2Convert::SignatureVerificationError
  # reject the request (400)
end
```

## Error handling

```ruby
begin
  client.convert("photo.png", "jpg").save("photo.jpg")
rescue Api2Convert::ValidationError    # bad target / option
rescue Api2Convert::AuthenticationError # bad or missing API key
rescue Api2Convert::RateLimitError => e # too many requests — retry after e.retry_after
rescue Api2Convert::ConversionFailedError => e # the job failed — inspect e.errors
end
```

Transient failures (429 / 5xx / network) are retried automatically with capped,
jittered exponential backoff; a non-idempotent `POST` is never blindly replayed.

## Power user: the full job API

```ruby
job = client.jobs.create(
  "process"    => false,
  "conversion" => [{ "target" => "pdf", "options" => { "pdf_a" => true } }]
)

client.jobs.upload(job, "contract.docx")                              # local file
client.jobs.add_input(job.id, "type" => "remote",
                              "source" => "https://example.com/appendix.docx") # or URL

client.jobs.start(job.id)
done = client.jobs.wait(job.id, 120)

done.output.each { |output| client.download(output).save("out/") }
```

## Discover options

```ruby
client.options("jpg") # => { "quality" => {...}, "width" => {...}, ... }
```

## Configuration

```ruby
client = Api2Convert::Client.new(
  "YOUR_API_KEY",
  base_url:          "https://api.api2convert.com/v2", # custom API host
  timeout:           30,   # per-request network timeout (seconds)
  max_retries:       2,    # automatic retries for transient failures
  poll_interval:     1.0,  # first poll interval (seconds)
  poll_max_interval: 5.0,  # backoff cap (seconds)
  poll_timeout:      300   # give up waiting after this many seconds
)
```

## Development

```console
$ bundle install
$ bundle exec rake spec           # offline unit suite
$ bundle exec rake spec:security  # independent security suite (real loopback servers)
$ bundle exec rake check          # rubocop + unit + security — the guardrail
```

Live conformance tests hit the real API and are skipped unless a key is present:

```console
$ API2CONVERT_API_KEY=<your key> bundle exec rake spec:live
```

Each guide has a runnable, self-contained example under [`examples/`](examples/),
and the [live conformance suite](spec/live/conformance_spec.rb) mirrors every one
of them (same operation, plus assertions) so a published version is always
verified end to end. It runs automatically against the real API on every release
tag (see `.github/workflows/live-conformance.yml`).

| # | Example | What it shows |
|---|---------|---------------|
| 1 | [`quickstart.rb`](examples/quickstart.rb) | Convert a remote URL, fetch the job, download the output |
| 2 | [`convert_files.rb`](examples/convert_files.rb) | Browse the conversions catalog, then convert |
| 3 | [`uploading_files.rb`](examples/uploading_files.rb) | One-call upload + convert of a local file |
| 4 | [`job_lifecycle.rb`](examples/job_lifecycle.rb) | Drive create → add input → start → wait → outputs by hand |
| 5 | [`add_watermark.rb`](examples/add_watermark.rb) | Stamp a PDF with an image (two remote inputs) |
| 6 | [`create_thumbnails.rb`](examples/create_thumbnails.rb) | Render a thumbnail of the first PDF page |
| 7 | [`compress_files.rb`](examples/compress_files.rb) | Compress an image with the compress operation |
| 8 | [`create_archives.rb`](examples/create_archives.rb) | Bundle remote files into a ZIP |
| 9 | [`create_hashes.rb`](examples/create_hashes.rb) | Compute a file's SHA-256 checksum |
| 10 | [`extract_assets.rb`](examples/extract_assets.rb) | Extract embedded assets from a document |
| 11 | [`file_analysis.rb`](examples/file_analysis.rb) | Extract file metadata as JSON |
| 12 | [`compare_files.rb`](examples/compare_files.rb) | Diff two images with compare-image |
| 13 | [`capture_website.rb`](examples/capture_website.rb) | Screenshot a page with the screenshot engine |
| 14 | [`audio_operations.rb`](examples/audio_operations.rb) | Re-encode audio to AAC |
| 15 | [`image_operations.rb`](examples/image_operations.rb) | Resize an image |
| 16 | [`webhooks.rb`](examples/webhooks.rb) | Start an async job with a callback URL |
| 17 | [`presets.rb`](examples/presets.rb) | List saved conversion presets |
| 18 | [`statistics.rb`](examples/statistics.rb) | Read monthly API usage |
| 19 | [`rate-limits.rb`](examples/rate-limits.rb) | Inspect the account's contracts |
| 20 | [`authentication.rb`](examples/authentication.rb) | Verify the API key by listing jobs |

A companion [`webhook.rb`](examples/webhook.rb) is a tiny Rack receiver that
verifies the callback signature — the other side of example 16.

Run any example with your key in the environment:

```console
$ API2CONVERT_API_KEY=<your key> ruby -Ilib examples/quickstart.rb
```

If your machine's Ruby is older than the gem targets, run the guardrail on a
supported Ruby with the bundled `Dockerfile`:

```console
$ docker build -t api2convert-ruby .
$ docker run --rm api2convert-ruby                        # rake check on Ruby 3.x
$ docker build --build-arg RUBY_VERSION=3.4 -t a2c:3.4 .  # pin a specific version
```

## License

MIT © Qaamgo Media GmbH
