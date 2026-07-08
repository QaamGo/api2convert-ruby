# frozen_string_literal: true

# Extract Assets — pull the embedded assets out of a document.
#
#   API2CONVERT_API_KEY=<your key> ruby -Ilib examples/extract_assets.rb

require "api2convert"

DOCX = "https://example-files.online-convert.com/document/docx/example.docx"

client = Api2Convert::Client.new # reads API2CONVERT_API_KEY

result = client.convert(DOCX, "extract-assets", category: "operation")
puts "job #{result.job.id} is #{result.job.status.code}"

result.outputs.each { |output| puts output.uri }
