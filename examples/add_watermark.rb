# frozen_string_literal: true

# Add a Watermark — stamp a PDF with an image using two remote inputs.
#
#   API2CONVERT_API_KEY=<your key> ruby -Ilib examples/add_watermark.rb

require "api2convert"

PDF = "https://example-files.online-convert.com/document/pdf/example.pdf"
PNG = "https://example-files.online-convert.com/raster%20image/png/example.png"

client = Api2Convert::Client.new # reads API2CONVERT_API_KEY

# Create a job with two inputs (the document and the stamp image) and start it.
job = client.jobs.create(
  {
    "process" => true,
    "input" => [
      { "type" => "remote", "source" => PDF },
      { "type" => "remote", "source" => PNG }
    ],
    "conversion" => [
      {
        "category" => "document",
        "target" => "pdf",
        "options" => { "stamp" => true, "alignment" => "center" }
      }
    ]
  }
)

done = client.jobs.wait(job.id)
puts "job #{done.id} is #{done.status.code}"

outputs = client.jobs.outputs(job.id)
outputs.each { |output| puts output.uri }
