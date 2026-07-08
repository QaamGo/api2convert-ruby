# frozen_string_literal: true

# Job Lifecycle — drive create -> add input -> start -> wait -> outputs by hand.
#
#   API2CONVERT_API_KEY=<your key> ruby -Ilib examples/job_lifecycle.rb

require "api2convert"

JPG = "https://example-files.online-convert.com/raster%20image/jpg/example.jpg"

client = Api2Convert::Client.new # reads API2CONVERT_API_KEY

# Stage a job (process: false) so we can attach inputs before starting.
job = client.jobs.create(
  { "process" => false, "conversion" => [{ "category" => "image", "target" => "png" }] }
)
puts "created job #{job.id}"

# Attach a remote input, then start processing.
client.jobs.add_input(job.id, { "type" => "remote", "source" => JPG })
client.jobs.start(job.id)

# Poll to a terminal status (raises on a failed job by default).
done = client.jobs.wait(job.id)
puts "job #{done.id} is #{done.status.code}"

# List the produced outputs.
outputs = client.jobs.outputs(job.id)
outputs.each { |output| puts output.uri }
