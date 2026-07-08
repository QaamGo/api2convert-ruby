# frozen_string_literal: true

# Create Hashes — compute the SHA-256 checksum of a remote file.
#
#   API2CONVERT_API_KEY=<your key> ruby -Ilib examples/create_hashes.rb

require "api2convert"

ZIP = "https://example-files.online-convert.com/archive/zip/example.zip"

client = Api2Convert::Client.new # reads API2CONVERT_API_KEY

result = client.convert(ZIP, "sha256", category: "hash")

# The hash is returned as the output file's contents.
puts "sha256: #{result.contents}"

path = result.save("output/")
puts "saved #{path} (#{File.size(path)} bytes)"
