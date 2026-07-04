# frozen_string_literal: true

require "openssl"
require "json"

RSpec.describe Api2Convert::Webhook::Verifier do
  let(:secret) { "whsec_test" }
  let(:payload) { JSON.generate("id" => "job-1", "status" => { "code" => "completed" }) }
  let(:signature) { OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, payload) }

  it "accepts a valid signature and returns a typed event" do
    event = described_class.new.construct_event(payload, signature, secret)
    expect(event.job.id).to eq("job-1")
    expect(event.job).to be_completed
    expect(event.payload).to eq(JSON.parse(payload))
  end

  it "rejects a tampered payload" do
    expect { described_class.new.construct_event("#{payload} ", signature, secret) }
      .to raise_error(Api2Convert::SignatureVerificationError)
  end

  it "rejects an equal-length wrong signature without a length crash" do
    wrong = "f" * signature.length
    expect { described_class.new.construct_event(payload, wrong, secret) }
      .to raise_error(Api2Convert::SignatureVerificationError)
  end

  it "raises when a secret is set but the signature is missing" do
    expect { described_class.new.construct_event(payload, nil, secret) }
      .to raise_error(Api2Convert::SignatureVerificationError, /Missing/)
  end

  it "treats an empty secret as a deliberate verification bypass" do
    event = described_class.new.construct_event(payload, nil, "")
    expect(event.job.id).to eq("job-1")
  end

  it "parses without verifying" do
    expect(described_class.new.parse(payload).job.id).to eq("job-1")
  end

  it "raises on invalid JSON" do
    expect { described_class.new.parse("{not json") }
      .to raise_error(Api2Convert::SignatureVerificationError, /not valid JSON/)
  end

  it "raises when the payload is not a JSON object" do
    expect { described_class.new.parse("[1,2,3]") }
      .to raise_error(Api2Convert::SignatureVerificationError, /not a JSON object/)
  end

  it "is reachable without a client via Api2Convert.webhooks" do
    expect(Api2Convert.webhooks).to be_a(described_class)
    expect(Api2Convert::Client.webhooks).to be_a(described_class)
  end
end
