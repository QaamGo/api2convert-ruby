# frozen_string_literal: true

# Image Operations — resize an image with the resize-image operation.
#
#   API2CONVERT_API_KEY=<your key> ruby -Ilib examples/image_operations.rb

require "api2convert"

JPG = "https://example-files.online-convert.com/raster%20image/jpg/example.jpg"

client = Api2Convert::Client.new # reads API2CONVERT_API_KEY

result = client.convert(
  JPG,
  "resize-image",
  { "width" => 800, "height" => 600, "resize_by" => "px", "resize_handling" => "keep_aspect_ratio_crop" },
  category: "operation"
)

path = result.save("output/")
puts "saved #{path} (#{File.size(path)} bytes)"
