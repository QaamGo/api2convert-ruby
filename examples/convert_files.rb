# frozen_string_literal: true

# Convert Files — browse the conversions catalog, then convert.
#
#   API2CONVERT_API_KEY=<your key> ruby -Ilib examples/convert_files.rb

require "api2convert"

JPG = "https://example-files.online-convert.com/raster%20image/jpg/example.jpg"

client = Api2Convert::Client.new # reads API2CONVERT_API_KEY

# The whole catalog: every supported target and its options.
all = client.conversions.list
puts "#{all.length} conversions available"

# Narrow it down: which conversions produce a PNG image?
png = client.conversions.list("image", "png")
puts "#{png.length} way(s) to produce png"

# Now convert a JPG to PNG.
result = client.convert(JPG, "png", category: "image")
path = result.save("convert-files-output.png")
puts "saved #{path} (#{File.size(path)} bytes)"
