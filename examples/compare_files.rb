# frozen_string_literal: true

# Compare Files — diff two images with the compare-image operation.
#
#   API2CONVERT_API_KEY=<your key> ruby -Ilib examples/compare_files.rb

require "api2convert"

JPG_SMALL = "https://example-files.online-convert.com/raster%20image/jpg/example_small.jpg"
JPG = "https://example-files.online-convert.com/raster%20image/jpg/example.jpg"

client = Api2Convert::Client.new # reads API2CONVERT_API_KEY

job = client.jobs.create(
  {
    "process" => true,
    "input" => [
      { "type" => "remote", "source" => JPG_SMALL },
      { "type" => "remote", "source" => JPG }
    ],
    "conversion" => [
      {
        "category" => "operation",
        "target" => "compare-image",
        "options" => { "method" => "ssim", "threshold" => 5, "diff_color" => "red" }
      }
    ]
  }
)

done = client.jobs.wait(job.id)
puts "job #{done.id} is #{done.status.code}"

client.jobs.outputs(job.id).each { |output| puts output.uri }
