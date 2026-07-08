# frozen_string_literal: true

# Webhooks — start a conversion and be notified via a callback URL.
#
#   API2CONVERT_API_KEY=<your key> ruby -Ilib examples/webhooks.rb
#
# convert_async returns immediately with a started job; the API POSTs to your
# callback when it finishes. See examples/webhook.rb for a receiver that verifies
# the callback signature.

require "api2convert"

DOCX = "https://example-files.online-convert.com/document/docx/example.docx"

client = Api2Convert::Client.new # reads API2CONVERT_API_KEY

job = client.convert_async(
  DOCX, "pdf",
  callback: "https://your-app.example.com/api2convert/webhook",
  category: "document"
)

puts "started job #{job.id} (#{job.status.code})"
puts "the API will POST to the callback URL when it completes"
