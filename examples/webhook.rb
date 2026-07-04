# frozen_string_literal: true

# A tiny Rack app that verifies API2Convert webhook callbacks.
#
#   API2CONVERT_WEBHOOK_SECRET=<your secret> rackup -Ilib examples/webhook.rb
#
# Point your job's `callback` URL at this endpoint (see convert_async). Until
# signed webhooks are enabled for your account no signature is sent — leave the
# secret empty to skip verification, or use Api2Convert.webhooks.parse.

require "api2convert"
require "rack"

SECRET = ENV.fetch("API2CONVERT_WEBHOOK_SECRET", "")

app = lambda do |env|
  request = Rack::Request.new(env)
  payload = request.body.read
  signature = env["HTTP_X_OC_SIGNATURE"]

  begin
    event = Api2Convert.webhooks.construct_event(payload, signature, SECRET)
    job = event.job
    warn "job #{job.id} is now #{job.status.code}"
    [200, { "content-type" => "text/plain" }, ["ok"]]
  rescue Api2Convert::SignatureVerificationError => e
    warn "rejected webhook: #{e.message}"
    [400, { "content-type" => "text/plain" }, ["invalid signature"]]
  end
end

run app
