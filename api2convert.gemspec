# frozen_string_literal: true

require_relative "lib/api2convert/version"

Gem::Specification.new do |spec|
  spec.name = "api2convert"
  spec.version = Api2Convert::VERSION
  spec.authors = ["Qaamgo Media GmbH"]

  spec.summary = "Official Ruby SDK for the API2Convert file-conversion API."
  spec.description =
    "Convert, compress and transform images, documents, audio, video, ebooks, " \
    "archives and CAD — and run operations like OCR, merge, thumbnail and website " \
    "capture — in one line of code."
  spec.homepage = "https://www.api2convert.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "homepage_uri" => "https://www.api2convert.com",
    "documentation_uri" => "https://www.api2convert.com/documentation",
    "source_code_uri" => "https://github.com/QaamGo/api2convert-ruby",
    "bug_tracker_uri" => "https://github.com/QaamGo/api2convert-ruby/issues",
    "changelog_uri" => "https://github.com/QaamGo/api2convert-ruby/blob/main/docs/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  # Resolve globs relative to this gemspec, not the caller's working directory.
  spec.files = Dir.chdir(__dir__) do
    Dir[
      "lib/**/*.rb",
      "docs/**/*",
      "openapi/**/*.json",
      "examples/**/*.rb",
      "README.md",
      "LICENSE",
      "AGENTS.md"
    ]
  end
  spec.require_paths = ["lib"]

  # Zero runtime dependencies: the SDK is built entirely on the Ruby standard
  # library (net/http, json, openssl, uri, securerandom, stringio, fileutils),
  # mirroring the Node.js SDK's zero-dependency stance.
end
