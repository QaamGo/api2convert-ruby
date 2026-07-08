# frozen_string_literal: true

# Rate Limits — inspect your account's contracts (quotas and limits).
#
#   API2CONVERT_API_KEY=<your key> ruby -Ilib examples/rate_limits.rb

require "api2convert"

client = Api2Convert::Client.new # reads API2CONVERT_API_KEY

contracts = client.contracts.get
puts contracts.inspect
