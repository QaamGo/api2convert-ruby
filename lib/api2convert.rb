# frozen_string_literal: true

# Official Ruby SDK for the API2Convert file-conversion API.
#
# Convert, compress and transform images, documents, audio, video, ebooks,
# archives and CAD — and run operations like OCR, merge, thumbnail and website
# capture — in one line of code:
#
#   require "api2convert"
#
#   client = Api2Convert::Client.new("YOUR_API_KEY")
#   client.convert("invoice.docx", "pdf").save("invoice.pdf")
#
# It is one of five official ports (PHP, Python, Java, Node.js, Ruby) that all
# implement the same language-agnostic contract in `docs/SDK_CONTRACT.md`.
module Api2Convert
end

require_relative "api2convert/version"
require_relative "api2convert/errors"
require_relative "api2convert/config"
require_relative "api2convert/support/data"
require_relative "api2convert/support/secret"
require_relative "api2convert/support/redactor"
require_relative "api2convert/job_status"
require_relative "api2convert/input_type"
require_relative "api2convert/cloud_provider"

require_relative "api2convert/model/status"
require_relative "api2convert/model/output_target"
require_relative "api2convert/model/cloud_input"
require_relative "api2convert/model/conversion"
require_relative "api2convert/model/input_file"
require_relative "api2convert/model/output_file"
require_relative "api2convert/model/job_message"
require_relative "api2convert/model/preset"
require_relative "api2convert/model/job"

require_relative "api2convert/http/request"
require_relative "api2convert/http/response"
require_relative "api2convert/http/net_http_sender"
require_relative "api2convert/http/transport"

require_relative "api2convert/upload/multipart_stream"
require_relative "api2convert/upload/file_uploader"

require_relative "api2convert/resource/jobs"
require_relative "api2convert/resource/conversions"
require_relative "api2convert/resource/presets"
require_relative "api2convert/resource/stats"
require_relative "api2convert/resource/contracts"

require_relative "api2convert/webhook/event"
require_relative "api2convert/webhook/verifier"

require_relative "api2convert/result"
require_relative "api2convert/client"

module Api2Convert
  # Webhook verifier — usable without a configured client.
  #
  #   event = Api2Convert.webhooks.construct_event(raw_body, signature, secret)
  def self.webhooks
    Webhook::Verifier.new
  end
end
