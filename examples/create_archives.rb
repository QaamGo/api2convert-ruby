# frozen_string_literal: true

# Create Archives — bundle several remote files into a single ZIP.
#
#   API2CONVERT_API_KEY=<your key> ruby -Ilib examples/create_archives.rb

require "api2convert"

PDF = "https://example-files.online-convert.com/document/pdf/example.pdf"
PNG = "https://example-files.online-convert.com/raster%20image/png/example.png"

client = Api2Convert::Client.new # reads API2CONVERT_API_KEY

job = client.jobs.create(
  {
    "process" => true,
    "input" => [
      { "type" => "remote", "source" => PDF },
      { "type" => "remote", "source" => PNG }
    ],
    "conversion" => [{ "category" => "archive", "target" => "zip" }]
  }
)

done = client.jobs.wait(job.id)
puts "job #{done.id} is #{done.status.code}"

outputs = client.jobs.outputs(job.id)
outputs.each { |output| puts output.uri }
