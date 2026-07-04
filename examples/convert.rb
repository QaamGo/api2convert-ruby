# frozen_string_literal: true

# Minimal synchronous conversion example.
#
#   API2CONVERT_API_KEY=<your key> ruby -Ilib examples/convert.rb path/to/photo.png jpg out.jpg
#
# Falls back to converting a public sample image when no source is given.

require "api2convert"

source = ARGV[0] || "https://example-files.online-convert.com/raster%20image/jpg/example.jpg"
target = ARGV[1] || "png"
destination = ARGV[2] || "output.#{target}"

client = Api2Convert::Client.new # reads API2CONVERT_API_KEY

result = client.convert(source, target)
path = result.save(destination)

puts "Converted #{source} -> #{path} (#{File.size(path)} bytes)"
