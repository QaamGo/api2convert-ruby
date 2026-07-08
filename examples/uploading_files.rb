# frozen_string_literal: true

# Uploading Files — convert a local file in one call (convert() uploads it).
#
#   API2CONVERT_API_KEY=<your key> ruby -Ilib examples/uploading_files.rb

require "api2convert"
require "base64"
require "tmpdir"

# A minimal valid 1x1 PNG so the example needs no binary fixture on disk.
ONE_PX_PNG = Base64.decode64(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
)

client = Api2Convert::Client.new # reads API2CONVERT_API_KEY

Dir.mktmpdir("a2c-upload") do |dir|
  source = File.join(dir, "pixel.png")
  File.binwrite(source, ONE_PX_PNG)

  # Hand convert() a local path — it stages the job, uploads the file to the
  # per-job upload server, starts it and polls to completion.
  result = client.convert(source, "png", category: "image")
  path = result.save("uploading-files-output.png")
  puts "saved #{path} (#{File.size(path)} bytes)"
end
