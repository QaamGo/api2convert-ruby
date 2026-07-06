# frozen_string_literal: true

require "stringio"

RSpec.describe Api2Convert::Http::Transport do
  describe "authenticated requests" do
    it "sends the API key in the X-Oc-Api-Key header and JSON content type on a body" do
      client, sender = make_client
      sender.add_json(200, "id" => "job-1", "status" => { "code" => "incomplete" })
      client.jobs.create("conversion" => [{ "target" => "pdf" }])

      req = sender.last
      expect(req.method).to eq("POST")
      expect(req.url).to end_with("/v2/jobs")
      expect(req.header("X-Oc-Api-Key")).to eq("test-key")
      expect(req.header("Content-Type")).to eq("application/json")
      expect(req.header("Accept")).to eq("application/json")
      expect(req.header("User-Agent")).to match(%r{\Aapi2convert-ruby/})
      expect(req.json).to eq("conversion" => [{ "target" => "pdf" }])
    end

    it "encodes query params without ever putting them in a header value" do
      client, sender = make_client
      sender.add_json(200, [])
      client.jobs.list("completed", 3)
      expect(sender.last.query).to include("page=3", "status=completed")
    end

    it "sends an Idempotency-Key header when a key is given" do
      client, sender = make_client
      sender.add_json(200, "id" => "j", "status" => { "code" => "created" })
      client.jobs.create({ "conversion" => [] }, "idem-123")
      expect(sender.last.header("Idempotency-Key")).to eq("idem-123")
    end
  end

  describe "error mapping" do
    {
      401 => Api2Convert::AuthenticationError,
      403 => Api2Convert::AuthenticationError,
      402 => Api2Convert::PaymentRequiredError,
      404 => Api2Convert::NotFoundError,
      400 => Api2Convert::ValidationError,
      422 => Api2Convert::ValidationError,
      418 => Api2Convert::ApiError
    }.each do |status, klass|
      it "maps HTTP #{status} to #{klass}" do
        client, sender = make_client({ max_retries: 0 })
        sender.add_json(status, { "message" => "boom" }, "X-Request-Id" => "req-9")
        expect { client.jobs.get("j") }.to raise_error(klass) do |error|
          expect(error.status_code).to eq(status)
          expect(error.message).to eq("boom")
          expect(error.request_id).to eq("req-9")
          expect(error.body).to eq("message" => "boom")
        end
      end
    end

    it "maps 429 to RateLimitError carrying retry_after" do
      client, sender = make_client({ max_retries: 0 })
      sender.add_json(429, { "message" => "slow down" }, "Retry-After" => "17")
      expect { client.jobs.get("j") }.to raise_error(Api2Convert::RateLimitError) do |error|
        expect(error.retry_after).to eq(17)
      end
    end

    it "maps 5xx to ServerError once retries are exhausted" do
      client, sender = make_client({ max_retries: 0 })
      sender.add_json(503, "message" => "unavailable")
      expect { client.jobs.get("j") }.to raise_error(Api2Convert::ServerError)
    end

    it "raises NetworkError for a 2xx with a non-JSON body" do
      client, sender = make_client
      sender.add_raw(200, "<html>not json</html>")
      expect { client.jobs.get("j") }.to raise_error(Api2Convert::NetworkError)
    end
  end

  describe "retries and backoff" do
    it "retries an idempotent GET on a 503 then succeeds, sleeping once" do
      client, sender, sleeps = make_client({ max_retries: 2 })
      sender.add_json(503, "message" => "try later")
      sender.add_json(200, "id" => "j", "status" => { "code" => "completed" })
      job = client.jobs.get("j")
      expect(job.id).to eq("j")
      expect(sender.requests.length).to eq(2)
      expect(sleeps.length).to eq(1)
    end

    it "retries a GET on a transport error" do
      client, sender = make_client({ max_retries: 1 })
      sender.add_error(SocketError.new("dns fail"))
      sender.add_json(200, "id" => "j", "status" => { "code" => "completed" })
      expect(client.jobs.get("j").id).to eq("j")
      expect(sender.requests.length).to eq(2)
    end

    it "does NOT retry a non-idempotent POST on a 500 (no duplicate jobs)" do
      client, sender = make_client({ max_retries: 3 })
      sender.add_json(500, "message" => "server")
      expect { client.jobs.create("conversion" => []) }.to raise_error(Api2Convert::ServerError)
      expect(sender.requests.length).to eq(1)
    end

    it "DOES retry a POST on a 429" do
      client, sender = make_client({ max_retries: 2 })
      sender.add_json(429, "message" => "rate")
      sender.add_json(200, "id" => "j", "status" => { "code" => "created" })
      expect(client.jobs.create("conversion" => []).id).to eq("j")
      expect(sender.requests.length).to eq(2)
    end

    it "honors a positive Retry-After for the backoff delay (capped, not jittered)" do
      client, sender, sleeps = make_client({ max_retries: 1 })
      sender.add_json(503, { "message" => "later" }, "Retry-After" => "42")
      sender.add_json(200, "id" => "j", "status" => { "code" => "created" })
      client.jobs.get("j")
      expect(sleeps).to eq([42.0])
    end

    it "caps an absurd Retry-After to the ceiling" do
      client, sender, sleeps = make_client({ max_retries: 1 })
      sender.add_json(503, { "message" => "later" }, "Retry-After" => "99999")
      sender.add_json(200, "id" => "j", "status" => { "code" => "created" })
      client.jobs.get("j")
      expect(sleeps).to eq([Api2Convert::Http::Transport::MAX_RETRY_AFTER_SECONDS])
    end

    it "never crashes on a non-finite Retry-After (falls back to exponential backoff)" do
      client, sender, sleeps = make_client({ max_retries: 1 })
      sender.add_json(503, { "message" => "later" }, "Retry-After" => "1e400")
      sender.add_json(200, "id" => "j", "status" => { "code" => "created" })
      expect { client.jobs.get("j") }.not_to raise_error
      expect(sleeps.length).to eq(1)
      expect(sleeps.first).to be <= Api2Convert::Http::Transport::MAX_BACKOFF_SECONDS
    end

    it "treats a non-finite Retry-After on a 429 as an unknown retry_after" do
      client, sender = make_client({ max_retries: 0 })
      sender.add_json(429, { "message" => "slow" }, "Retry-After" => "1e400")
      expect { client.jobs.get("j") }.to raise_error(Api2Convert::RateLimitError) do |error|
        expect(error.retry_after).to be_nil
      end
    end
  end

  describe "download" do
    def transport_for(client)
      client.instance_variable_get(:@transport)
    end

    it "streams a successful body into the sink and returns nil (no whole-body buffer)" do
      client, sender = make_client
      sender.add_raw(200, "STREAMED-BYTES")
      sink = StringIO.new
      result = transport_for(client).download("https://dl.example/x", {}, sink: sink)
      expect(result).to be_nil
      expect(sink.string).to eq("STREAMED-BYTES")
    end

    it "buffers into memory and returns the body when no sink is given" do
      client, sender = make_client
      sender.add_raw(200, "BUFFERED-BYTES")
      expect(transport_for(client).download("https://dl.example/x", {})).to eq("BUFFERED-BYTES")
    end

    it "raises NetworkError on an unexpected 3xx (never writes a redirect as the file)" do
      client, sender = make_client
      sender.add_raw(302, "<html>redirect</html>", "Location" => "https://evil.example/steal")
      sink = StringIO.new
      expect do
        transport_for(client).download(
          "https://dl.example/x", { "X-Oc-Download-Password" => "pw" },
          follow_redirects: false, sink: sink
        )
      end.to raise_error(Api2Convert::NetworkError, /HTTP 302/)
      expect(sink.string).to eq("") # the redirect body never reached the sink
    end
  end
end
