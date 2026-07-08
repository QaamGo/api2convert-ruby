# frozen_string_literal: true

# Compress Files — shrink an image with the compress operation.
#
#   API2CONVERT_API_KEY=<your key> ruby -Ilib examples/compress_files.rb

require "api2convert"

JPG = "https://example-files.online-convert.com/raster%20image/jpg/example.jpg"

client = Api2Convert::Client.new # reads API2CONVERT_API_KEY

result = client.convert(
  JPG, "compress", { "compression_level" => "high" }, category: "operation"
)

path = result.save("output/")
puts "saved #{path} (#{File.size(path)} bytes)"
