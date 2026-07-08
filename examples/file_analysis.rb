# frozen_string_literal: true

# File Analysis — extract a file's metadata as JSON.
#
#   API2CONVERT_API_KEY=<your key> ruby -Ilib examples/file_analysis.rb

require "api2convert"

JPG = "https://example-files.online-convert.com/raster%20image/jpg/example.jpg"

client = Api2Convert::Client.new # reads API2CONVERT_API_KEY

result = client.convert(JPG, "json", category: "metadata")
puts "job #{result.job.id} is #{result.job.status.code}"

# The analysis result is the output file's JSON body.
puts result.contents
