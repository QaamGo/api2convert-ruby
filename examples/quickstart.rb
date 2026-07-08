# frozen_string_literal: true

# Quickstart — convert a remote file, inspect the job, download the result.
#
#   API2CONVERT_API_KEY=<your key> ruby -Ilib examples/quickstart.rb

require "api2convert"

JPG = "https://example-files.online-convert.com/raster%20image/jpg/example.jpg"

client = Api2Convert::Client.new # reads API2CONVERT_API_KEY

# One-call convert of a remote URL (create -> poll -> ready to download).
result = client.convert(JPG, "png", category: "image")

# Fetch the finished job by id and print its status.
job = client.jobs.get(result.job.id)
puts "job #{job.id} is #{job.status.code}"

# Download the produced output.
path = result.save("quickstart-output.png")
puts "saved #{path} (#{File.size(path)} bytes)"
