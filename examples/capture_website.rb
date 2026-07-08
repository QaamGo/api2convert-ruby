# frozen_string_literal: true

# Capture a Website — screenshot a page with the screenshot engine.
#
#   API2CONVERT_API_KEY=<your key> ruby -Ilib examples/capture_website.rb

require "api2convert"

client = Api2Convert::Client.new # reads API2CONVERT_API_KEY

job = client.jobs.create(
  {
    "process" => true,
    "input" => [
      {
        "type" => "remote",
        "source" => "https://www.online-convert.com",
        "engine" => "screenshot",
        "options" => { "screen_width" => 1280, "screen_height" => 1024, "device_scale_factor" => 1 }
      }
    ],
    "conversion" => [{ "category" => "image", "target" => "png" }]
  }
)

done = client.jobs.wait(job.id)
puts "job #{done.id} is #{done.status.code}"

client.jobs.outputs(job.id).each { |output| puts output.uri }
