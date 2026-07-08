# frozen_string_literal: true

# Statistics — read your API usage for a given month.
#
#   API2CONVERT_API_KEY=<your key> ruby -Ilib examples/statistics.rb

require "api2convert"

client = Api2Convert::Client.new # reads API2CONVERT_API_KEY

stats = client.stats.month("2026-06")
puts stats.inspect
