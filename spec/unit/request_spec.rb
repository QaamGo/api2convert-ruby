# frozen_string_literal: true

RSpec.describe Api2Convert::Http::Request do
  describe "#inspect" do
    it "masks secret X-Api2convert-* header values so a log line or backtrace never leaks them" do
      request = described_class.new(
        method: "POST",
        url: "https://api.api2convert.com/v2/jobs",
        headers: {
          "X-Api2convert-Api-Key" => "sk_live_super_secret_key_1234",
          "X-Api2convert-Download-Password" => "s3cret-password",
          "Accept" => "application/json"
        }
      )

      output = request.inspect

      # The raw secrets never appear in cleartext...
      expect(output).not_to include("sk_live_super_secret_key_1234")
      expect(output).not_to include("s3cret-password")
      # ...they are routed through Secret.mask (last-4 form)...
      expect(output).to include("[FILTERED:...1234]")
      # ...while non-secret headers stay readable.
      expect(output).to include("application/json")
    end

    it "also masks the legacy X-Oc-* prefix, so the rename can never open a redaction gap" do
      request = described_class.new(
        method: "GET",
        url: "https://api.api2convert.com/v2/jobs",
        headers: { "X-Oc-Api-Key" => "legacy_secret_value_9999" }
      )

      expect(request.inspect).not_to include("legacy_secret_value_9999")
      expect(request.inspect).to include("[FILTERED:...9999]")
    end
  end
end
