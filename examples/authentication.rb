# frozen_string_literal: true

# Authentication — verify your API key by listing your jobs.
#
#   API2CONVERT_API_KEY=<your key> ruby -Ilib examples/authentication.rb

require "api2convert"

client = Api2Convert::Client.new # reads API2CONVERT_API_KEY

# A successful, authenticated call returns your jobs (empty on a fresh account).
jobs = client.jobs.list
puts "authenticated: #{jobs.length} job(s) visible"
