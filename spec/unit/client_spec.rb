# frozen_string_literal: true

require "stringio"

RSpec.describe Api2Convert::Client do
  describe "construction" do
    around do |example|
      previous = ENV.fetch("API2CONVERT_API_KEY", nil)
      begin
        example.run
      ensure
        if previous.nil?
          ENV.delete("API2CONVERT_API_KEY")
        else
          ENV["API2CONVERT_API_KEY"] = previous
        end
      end
    end

    it "raises when no key is given and the env var is unset" do
      ENV.delete("API2CONVERT_API_KEY")
      expect { described_class.new }.to raise_error(ArgumentError, /No API key/)
    end

    it "falls back to the API2CONVERT_API_KEY env var" do
      ENV["API2CONVERT_API_KEY"] = "env-key"
      expect { described_class.new("", http_sender: FakeHttpSender.new) }.not_to raise_error
    end
  end

  describe "#convert from a public URL" do
    it "creates a single started job with a remote input and polls to completion" do
      client, sender = make_client
      sender.add_json(200, "id" => "job-1", "status" => { "code" => "processing" })
      sender.add_json(200, "id" => "job-1", "status" => { "code" => "completed" },
                           "output" => [{ "uri" => "https://dl/x", "filename" => "out.png" }])

      result = client.convert("https://example.com/a.jpg", "png", { "quality" => 90 })

      create = sender.requests.first
      expect(create.method).to eq("POST")
      body = create.json
      expect(body["process"]).to be(true)
      expect(body["input"]).to eq([{ "type" => "remote", "source" => "https://example.com/a.jpg" }])
      expect(body["conversion"]).to eq([{ "target" => "png", "options" => { "quality" => 90 } }])
      expect(result.job).to be_completed
      expect(result.url).to eq("https://dl/x")
    end
  end

  describe "#convert from a local file" do
    it "stages the job, uploads, starts, then polls" do
      client, sender = make_client
      sender.add_json(200, "id" => "job-2", "status" => { "code" => "incomplete" },
                           "server" => "https://up.example", "token" => "tok")
      sender.add_json(200, "id" => "in-1", "type" => "upload") # upload
      sender.add_json(200, "id" => "job-2", "status" => { "code" => "processing" }) # start (PATCH)
      sender.add_json(200, "id" => "job-2", "status" => { "code" => "completed" },
                           "output" => [{ "uri" => "https://dl/y" }]) # wait -> get

      result = client.convert(StringIO.new("filebytes"), "pdf")

      methods = sender.requests.map(&:method)
      expect(methods).to eq(%w[POST POST PATCH GET])
      expect(sender.requests.first.json["process"]).to be(false)
      expect(sender.requests[1].header("X-Oc-Token")).to eq("tok")
      expect(sender.requests[2].json).to eq("process" => true)
      expect(result.job).to be_completed
    end
  end

  describe "#convert_async" do
    it "returns the started job without polling and sets notify_status with a callback" do
      client, sender = make_client
      sender.add_json(200, "id" => "job-3", "status" => { "code" => "processing" })

      job = client.convert_async("https://example.com/a.jpg", "png",
                                 callback: "https://hooks.example/cb")
      expect(job.id).to eq("job-3")
      expect(sender.requests.length).to eq(1)
      body = sender.last.json
      expect(body["callback"]).to eq("https://hooks.example/cb")
      expect(body["notify_status"]).to be(true)
    end

    it "sets download_passwords when a password is given" do
      client, sender = make_client
      sender.add_json(200, "id" => "j", "status" => { "code" => "processing" })
      client.convert_async("https://example.com/a.jpg", "png", download_password: "pw")
      expect(sender.last.json["download_passwords"]).to eq(["pw"])
    end
  end

  describe "#options" do
    it "is sugar for the conversions catalog options of a target" do
      client, sender = make_client
      sender.add_json(200, [{ "target" => "jpg", "options" => { "quality" => { "type" => "integer" } } }])
      expect(client.options("jpg")).to eq("quality" => { "type" => "integer" })
      expect(sender.last.query).to include("target=jpg")
    end
  end
end
