# frozen_string_literal: true

require "json"
require "openssl"
require "socket"
require "stringio"
require "tmpdir"

# Independent security suite — run in isolation with `rake spec:security` (or
# `rspec spec/security`). It is excluded from the default `rake spec` run.
#
# The redirect guarantees are proven with REAL loopback HTTP servers (see
# spec/support/loopback_server.rb), mirroring the Node.js / Java security suites:
# only a real cross-host 302 between real servers can demonstrate that the
# transport does not forward an `X-Oc-*` secret header to the redirect target.
# Header/query/traversal/webhook/ReDoS checks use the injected fake sender where a
# real network round-trip adds nothing.
RSpec.describe "security", :security do
  before { @servers = [] }
  after { @servers.each(&:close) }

  def start_server(&block)
    server = LoopbackServer.new(&block)
    @servers << server
    server
  end

  def output(attrs = {})
    Api2Convert::Model::OutputFile.from_hash({ "uri" => "https://dl.example/x" }.merge(attrs))
  end

  describe "secret hygiene" do
    it "never leaks the API key into an exception message or backtrace" do
      secret = "sk_live_super_secret_value_123"
      client, sender = make_client({ max_retries: 0 }, secret)
      sender.add_json(401, "message" => "Invalid API key.")

      error = nil
      begin
        client.jobs.get("job-x")
      rescue Api2Convert::AuthenticationError => e
        error = e
      end

      expect(error).not_to be_nil
      expect(error.message).not_to include(secret)
      expect(Array(error.backtrace).join("\n")).not_to include(secret)
      # ...but the key WAS sent as the auth header (the request was authenticated).
      expect(sender.last.header("X-Oc-Api-Key")).to eq(secret)
    end

    it "masks secrets in #inspect / #to_s so `p client` never prints them in cleartext" do
      key = "sk_live_super_secret_value_123"
      password = "dl_password_secret_987"
      client, = make_client({}, key)
      config = Api2Convert::Config.create(key)
      transport = client.instance_variable_get(:@transport)
      download = client.download(output, password)
      result = Api2Convert::Result::ConversionResult.new(
        Api2Convert::Model::Job.from_hash("id" => "j", "status" => { "code" => "completed" }),
        transport, 0, password
      )

      dumps = [
        client.inspect, client.to_s, config.inspect, config.to_s,
        transport.inspect, download.inspect, result.inspect
      ]
      dumps.each do |text|
        expect(text).not_to include(key)
        expect(text).not_to include(password)
      end
      # The key is still represented (redacted) so a dump stays useful for support.
      expect(config.inspect).to include("[FILTERED")
      expect(transport.inspect).to include("[FILTERED")
    end

    it "never places the API key in the URL or query string" do
      key = "sk_live_in_url_check"
      client, sender = make_client({}, key)
      sender.add_json(200, [])
      sender.add_json(200, [])
      client.options("jpg", "image")
      client.jobs.list("completed", 2)

      sender.requests.each do |req|
        expect(req.url).not_to include(key)
        expect(req.url.downcase).not_to match(/[?&](api[-_]?key|apikey|key)=/)
      end
    end
  end

  describe "redirect policy (real loopback servers)" do
    it "does not forward the account key across a cross-host redirect" do
      evil = start_server { |headers| { status: 200, body: "grabbed:#{headers["x-oc-api-key"]}" } }
      api = start_server { |_headers| { status: 302, headers: { "Location" => "#{evil.url}/steal" } } }

      client = real_client(base_url: "#{api.url}/v2")
      # An authenticated 3xx is surfaced as a typed error, not silently empty.
      expect { client.jobs.get("j") }.to raise_error(Api2Convert::NetworkError)

      expect(evil.hits).to eq(0)
      expect(api.hits).to eq(1)
      expect(api.headers_received.first["x-oc-api-key"]).to eq("secret-key")
    end

    it "follows storage redirects for a passwordless download" do
      storage = start_server { |_headers| { status: 200, body: "REDIRECTED-BYTES" } }
      dl = start_server { |_headers| { status: 302, headers: { "Location" => "#{storage.url}/file" } } }

      bytes = real_client.download(output("uri" => "#{dl.url}/result.bin")).contents
      expect(bytes).to eq("REDIRECTED-BYTES")
      expect(storage.hits).to eq(1)
    end

    it "authenticates uploads with the job token, never the account key, and never redirects" do
      evil = start_server { |_headers| { status: 200, body: "grabbed" } }
      upload_srv = start_server { |_headers| { status: 302, headers: { "Location" => "#{evil.url}/steal" } } }

      job = Api2Convert::Model::Job.from_hash(
        "id" => "job-9", "token" => "tok-abc",
        "server" => upload_srv.url, "status" => { "code" => "incomplete" }
      )
      begin
        real_client.jobs.upload(job, StringIO.new("hello"))
      rescue Api2Convert::Error
        nil
      end

      seen = upload_srv.headers_received.first
      expect(seen["x-oc-token"]).to eq("tok-abc")
      expect(seen["x-oc-api-key"]).to be_nil
      expect(evil.hits).to eq(0)
    end

    it "does not forward a download password across a cross-host redirect" do
      evil = start_server { |_headers| { status: 200, body: "grabbed" } }
      storage = start_server { |_headers| { status: 302, headers: { "Location" => "#{evil.url}/steal" } } }

      begin
        real_client.download(output("uri" => "#{storage.url}/f.pdf"), "s3cret").contents
      rescue Api2Convert::Error
        nil
      end

      expect(evil.hits).to eq(0)
      leaked = evil.headers_received.any? { |h| h.key?("x-oc-download-password") }
      expect(leaked).to be(false)
    end

    it "follows a redirect only for a passwordless download, not a password-protected one" do
      plain_target = start_server { |_headers| { status: 200, body: "REACHED" } }
      plain_hop = start_server do |_headers|
        { status: 302, headers: { "Location" => "#{plain_target.url}/x" } }
      end
      pw_target = start_server { |_headers| { status: 200, body: "REACHED" } }
      pw_hop = start_server { |_headers| { status: 302, headers: { "Location" => "#{pw_target.url}/x" } } }

      client = real_client
      expect(client.download(output("uri" => "#{plain_hop.url}/f")).contents).to eq("REACHED")
      expect(plain_target.hits).to eq(1)

      begin
        client.download(output("uri" => "#{pw_hop.url}/f"), "pw").contents
      rescue Api2Convert::Error
        nil
      end
      expect(pw_target.hits).to eq(0)
    end

    it "surfaces a malformed API-supplied download URI as a NetworkError" do
      expect { real_client.download(output("uri" => "https://exa mple.com/a b c")).contents }
        .to raise_error(Api2Convert::NetworkError)
    end
  end

  describe "streaming timeout semantics (real loopback)" do
    # A slow-but-steady streamed download must NOT be aborted by the request
    # timeout. Net::HTTP's read_timeout is per-read-block (not a whole-transfer
    # cap), so a body that trickles in over a span far exceeding the timeout still
    # completes as long as no single gap between chunks stalls past it. This pins
    # that the streamed body is bounded only by inter-chunk stalls, never a total.
    it "does not cap a slow streamed download whose total transfer exceeds the timeout" do
      # 4 chunks, 0.4s apart -> ~1.6s total transfer, each gap well under the 1s
      # timeout. A whole-transfer timeout would abort this; a per-read one must not.
      port, closer = start_trickle_server(%w[AA BB CC DD], gap: 0.4)
      client = Api2Convert::Client.new(
        "secret-key",
        max_retries: 0, timeout: 1, sleeper: ->(_seconds) {}, rng: -> { 0.0 }
      )

      Dir.mktmpdir do |dir|
        target = File.join(dir, "trickled.bin")
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        client.download(output("uri" => "http://127.0.0.1:#{port}/x")).save(target)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

        expect(File.binread(target)).to eq("AABBCCDD")
        expect(elapsed).to be > 1.0 # the transfer genuinely outlasted the timeout
      end
    ensure
      closer&.call
    end

    # A raw trickling HTTP/1.1 server: sends the status + Content-Length, then
    # dribbles the body one chunk per +gap+ seconds. Returns [port, closer].
    def start_trickle_server(chunks, gap:)
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      thread = Thread.new do
        conn = server.accept
        # Drain the request line + headers up to the blank separator line.
        while (line = conn.gets)
          break if ["\r\n", "\n"].include?(line)
        end
        conn.write("HTTP/1.1 200 OK\r\nContent-Length: #{chunks.join.bytesize}\r\n" \
                   "Connection: close\r\n\r\n")
        conn.flush
        chunks.each do |chunk|
          sleep(gap)
          conn.write(chunk)
          conn.flush
        end
        conn.close
      rescue StandardError
        nil
      end
      closer = lambda do
        begin
          server.close
        rescue StandardError
          nil
        end
        thread.kill
      end
      [port, closer]
    end
  end

  describe "control-plane response cap (real loopback)" do
    # A hostile or buggy API server must not be able to force an unbounded in-memory
    # read (OOM) on the control-plane (JSON / error) path. The SDK buffers that body
    # only up to NetHttpSender::MAX_RESPONSE_BYTES (16 MiB), mirroring the shipped Go
    # SDK's `maxResponseBytes = 16 << 20`. This proves the cap is EFFECTIVE: because
    # Net::HTTP is read in block form, the SDK accumulates chunk-by-chunk and aborts
    # the instant the cap is crossed — it never buffers the whole body first — unlike
    # a `res.body`-then-check cap, which would OOM before it could fire.
    it "rejects an over-cap API body with a typed error without buffering it whole" do
      cap = Api2Convert::Http::NetHttpSender::MAX_RESPONSE_BYTES
      # The server advertises and tries to stream 4x the cap. If the SDK buffered
      # unboundedly it would drain all of it; instead it must abort after ~the cap.
      total = cap * 4
      port, closer, written = start_flood_server(total)

      client = real_client(base_url: "http://127.0.0.1:#{port}/v2")
      expect { client.jobs.get("j") }
        .to raise_error(Api2Convert::NetworkError, /exceeds 16 MiB/)

      # The SDK stopped reading shortly past the cap — it did NOT drain all `total`
      # bytes into memory (socket-buffer slack allowed, but well under the flood).
      expect(written.call).to be < (cap * 2)
    ensure
      closer&.call
    end

    # A raw HTTP/1.1 server that advertises `total` bytes and floods them out in
    # 1 MiB chunks with no pause, recording how many it managed to write before the
    # peer hangs up. Returns [port, closer, written_reader].
    def start_flood_server(total)
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      written = 0
      mutex = Mutex.new
      thread = Thread.new do
        conn = server.accept
        while (line = conn.gets)
          break if ["\r\n", "\n"].include?(line)
        end
        conn.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n" \
                   "Content-Length: #{total}\r\nConnection: close\r\n\r\n")
        conn.flush
        chunk = "a" * (1024 * 1024)
        sent = 0
        while sent < total
          conn.write(chunk)
          sent += chunk.bytesize
          mutex.synchronize { written = sent }
        end
        conn.close
      rescue StandardError
        nil
      end
      closer = lambda do
        begin
          server.close
        rescue StandardError
          nil
        end
        thread.kill
      end
      [port, closer, -> { mutex.synchronize { written } }]
    end
  end

  describe "filesystem safety" do
    it "reduces a traversal filename to a basename that cannot escape the target directory" do
      client, sender = make_client
      sender.add_raw(200, "X")
      Dir.mktmpdir do |dir|
        path = client.download(output("filename" => "../../../etc/evil")).save(dir)
        expect(path).to eq(File.join(dir, "evil"))
      end
    end
  end

  describe "webhook signature verification" do
    let(:secret) { "whsec_test" }
    let(:payload) { JSON.generate("id" => "job-1", "status" => { "code" => "completed" }) }
    let(:signature) { OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, payload) }

    it "accepts a valid signature" do
      expect(Api2Convert.webhooks.construct_event(payload, signature, secret).job.id).to eq("job-1")
    end

    it "rejects a tampered payload" do
      expect { Api2Convert.webhooks.construct_event("#{payload} ", signature, secret) }
        .to raise_error(Api2Convert::SignatureVerificationError)
    end

    it "rejects an equal-length wrong signature (constant-time path, no length crash)" do
      wrong = "f" * signature.length
      expect { Api2Convert.webhooks.construct_event(payload, wrong, secret) }
        .to raise_error(Api2Convert::SignatureVerificationError)
    end

    it "treats an empty secret as a deliberate verification bypass" do
      expect(Api2Convert.webhooks.construct_event(payload, nil, "").job.id).to eq("job-1")
    end
  end

  describe "untrusted-JSON hardening" do
    it "hydrates a hostile payload without corrupting core objects and keeps string keys" do
      malicious = '{"__proto__":{"polluted":true},' \
                  '"constructor":{"prototype":{"polluted2":true}},"id":"job-1"}'

      event = Api2Convert.webhooks.parse(malicious)
      expect(event.job.id).to eq("job-1")
      # Ruby has no prototype chain, but confirm nothing global was mutated and the
      # keys are plain Strings (no symbol-DoS surface).
      expect({}.respond_to?(:polluted)).to be(false)
      expect({}.key?("polluted")).to be(false)
      expect(event.payload.keys).to all(be_a(String))
      expect(event.payload["__proto__"]).to eq("polluted" => true)
    end

    it "classifies input with an anchored, linear URL matcher (ReDoS-safe)" do
      pathological = "http#{"p" * 100_000}x"
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      matched = Api2Convert::Client::URL_RE.match?(pathological)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(matched).to be(false) # treated as a local path, not a remote input
      expect(elapsed).to be < 1.0
      expect(Api2Convert::Client::URL_RE.match?("https://example.com/x")).to be(true)
    end
  end
end
