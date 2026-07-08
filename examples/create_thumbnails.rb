# frozen_string_literal: true

# Create Thumbnails — render a thumbnail of the first PDF page.
#
#   API2CONVERT_API_KEY=<your key> ruby -Ilib examples/create_thumbnails.rb

require "api2convert"

PDF = "https://example-files.online-convert.com/document/pdf/example.pdf"

client = Api2Convert::Client.new # reads API2CONVERT_API_KEY

result = client.convert(
  PDF,
  "thumbnail",
  { "thumbnail_target" => "png", "width" => 300, "pages" => "first", "dpi" => 150 },
  category: "operation"
)

# Save into a directory so the API-provided filename is kept.
path = result.save("output/")
puts "saved #{path} (#{File.size(path)} bytes)"
