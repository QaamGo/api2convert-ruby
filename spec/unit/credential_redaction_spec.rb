# frozen_string_literal: true

# Cloud-connector fixture 3 — the credential redaction / isolation suite.
#
# The single secret `SUPERSECRET123` must never appear on any rendering/error
# path, and the fixed marker `[REDACTED]` must appear where a credentials object
# is rendered.
RSpec.describe "credential redaction" do
  secret = "SUPERSECRET123"
  marker = "[REDACTED]"

  # ---- 3a: object rendering --------------------------------------------------

  describe "3a — object rendering" do
    it "masks the whole credentials object of a CloudInput on every inspection path" do
      input = Api2Convert::Model::CloudInput.amazon_s3(
        bucket: "b", file: "f", accesskeyid: "AKIA", secretaccesskey: secret
      )

      [input.inspect, input.to_s, format("%s", input)].each do |rendered|
        expect(rendered).not_to include(secret)
        expect(rendered).to include(marker)
      end
      # Non-secret parameters still render.
      expect(input.inspect).to include("bucket")
    end

    it "masks the whole credentials object of an OutputTarget" do
      target = Api2Convert::Model::OutputTarget.of(
        Api2Convert::CloudProvider::FTP,
        parameters: { "host" => "ftp.example.com" },
        credentials: { "username" => "u", "password" => secret }
      )

      expect(target.inspect).not_to include(secret)
      expect(target.inspect).to include(marker)
    end
  end

  # ---- 3b + 3c: error text and error-body deep-walk --------------------------

  describe "3b/3c — error text and error-body deep-walk" do
    it "never leaks a submitted credential through the create-path error or its body" do
      client, sender = make_client({ max_retries: 0 })
      # A 422 whose decoded body echoes the submitted secret in a nested/dotted key
      # (belt-and-suspenders: the real API echoes field *names* only). The convert()
      # request body itself carried the secret in credentials.
      sender.add_json(422,
                      "message" => "Validation failed",
                      "errors" => { "input.0.credentials.secretaccesskey" => secret })

      error = nil
      begin
        client.convert(
          Api2Convert::Model::CloudInput.amazon_s3(
            bucket: "b", file: "f", accesskeyid: "AKIA", secretaccesskey: secret
          ),
          "jpg"
        )
      rescue Api2Convert::ValidationError => e
        error = e
      end

      expect(error).not_to be_nil
      # 3b: no secret in the message, backtrace, or anywhere on the exception.
      expect(error.message).not_to include(secret)
      expect(Array(error.backtrace).join("\n")).not_to include(secret)
      # 3c: the deep-walk masks the echoed secret to the marker on the body.
      dumped = JSON.generate(error.body)
      expect(dumped).not_to include(secret)
      expect(dumped).to include(marker)
    end

    it "never renders the request body (with its credentials) through Request#inspect" do
      request = Api2Convert::Http::Request.new(
        method: "POST",
        url: "https://api.api2convert.com/v2/jobs",
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate("credentials" => { "secretaccesskey" => secret })
      )
      expect(request.inspect).not_to include(secret)
      expect(request.to_s).not_to include(secret)
    end
  end

  # ---- 3d: sensitive parameters leaf -----------------------------------------

  describe "3d — sensitive parameters leaf" do
    it "masks a sensitive parameters key while leaving non-secret keys readable" do
      input = Api2Convert::Model::CloudInput.of(
        Api2Convert::CloudProvider::AMAZON_S3,
        parameters: { "token" => "PARAMSECRET", "bucket" => "b" }
      )

      expect(input.inspect).not_to include("PARAMSECRET")
      expect(input.inspect).to include(marker)
      # A non-secret key renders normally.
      expect(input.inspect).to include("bucket")
    end

    it "covers the full sensitive-key set case-insensitively via the Redactor" do
      params = {
        "Token" => "a", "PASSWORD" => "b", "passwd" => "c", "mySecret" => "d",
        "AccessKey" => "e", "keyfile" => "f", "credential" => "g",
        "passphrase" => "h", "SAS" => "i", "sig" => "j", "signature" => "k",
        "bucket" => "keep", "host" => "keep", "projectid" => "keep"
      }
      masked = Api2Convert::Support::Redactor.parameters(params)

      %w[Token PASSWORD passwd mySecret AccessKey keyfile credential passphrase
         SAS sig signature].each do |key|
        expect(masked[key]).to eq(marker)
      end
      expect(masked["bucket"]).to eq("keep")
      expect(masked["host"]).to eq("keep")
      expect(masked["projectid"]).to eq("keep")
    end
  end
end
