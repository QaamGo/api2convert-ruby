# frozen_string_literal: true

# Cloud-connector parity fixtures 1 (create-payload serialization) and 2 (read
# hydration), plus the unit behaviour of the new cloud types. The JSON shapes and
# assertions mirror the canonical fixtures shared across every SDK.
RSpec.describe "cloud connectors" do
  # The exact input descriptor fixture 1 expects the SDK to serialize.
  expected_input = {
    "type" => "cloud",
    "source" => "amazons3",
    "parameters" => { "bucket" => "my-bucket", "file" => "in/photo.png" },
    "credentials" => { "accesskeyid" => "AKIA_TEST", "secretaccesskey" => "SECRET_TEST" }
  }.freeze

  # The exact output_target descriptor fixture 1 expects — note: no `status` key.
  expected_output_target = {
    "type" => "ftp",
    "parameters" => { "host" => "ftp.example.com", "file" => "/out/photo.jpg" },
    "credentials" => { "username" => "u", "password" => "p" }
  }.freeze

  # ---- Fixture 1: create-payload (what convert() serializes) -----------------

  describe "fixture 1 — create-payload" do
    it "serializes a CloudInput and an OutputTarget passed via the convert control" do
      client, sender = make_client
      # create -> started job; wait() polls once to a completed job (no local output).
      sender.add_json(201, "id" => "job-1", "status" => { "code" => "incomplete" })
      sender.add_json(200, "id" => "job-1", "status" => { "code" => "completed" })

      input = Api2Convert::Model::CloudInput.amazon_s3(
        bucket: "my-bucket", file: "in/photo.png",
        accesskeyid: "AKIA_TEST", secretaccesskey: "SECRET_TEST"
      )
      target = Api2Convert::Model::OutputTarget.new(
        type: "ftp",
        parameters: { "host" => "ftp.example.com", "file" => "/out/photo.jpg" },
        credentials: { "username" => "u", "password" => "p" }
      )

      client.convert(input, "jpg", output_targets: [target])

      body = sender.requests.first.json
      # 1) a cloud input is a started job (like a remote URL), not staged/uploaded.
      expect(body["process"]).to be(true)
      # 2) input[0] carries the flat/lowercase keys exactly as the factory emits.
      expect(body["input"]).to eq([expected_input])
      # 3) output_target serializes {type,parameters,credentials} and NO status.
      expect(body["conversion"][0]["output_target"]).to eq([expected_output_target])
      expect(body["conversion"][0]["output_target"][0]).not_to have_key("status")
      # output targets never leak into the conversion options map.
      expect(body["conversion"][0]).not_to have_key("options")
    end

    it "produces a byte-identical output_target via the raw jobs.create path" do
      client, sender = make_client
      sender.add_json(201, "id" => "job-1", "status" => { "code" => "completed" })

      client.jobs.create(
        "process" => true,
        "input" => [
          Api2Convert::Model::CloudInput.amazon_s3(
            bucket: "my-bucket", file: "in/photo.png",
            accesskeyid: "AKIA_TEST", secretaccesskey: "SECRET_TEST"
          ).to_h
        ],
        "conversion" => [{
          "target" => "jpg",
          "output_target" => [
            Api2Convert::Model::OutputTarget.of(
              Api2Convert::CloudProvider::FTP,
              parameters: { "host" => "ftp.example.com", "file" => "/out/photo.jpg" },
              credentials: { "username" => "u", "password" => "p" }
            ).to_h
          ]
        }]
      )

      body = sender.requests.first.json
      # Both the convert() control and the raw create map yield the same bytes.
      expect(body["input"]).to eq([expected_input])
      expect(body["conversion"][0]["output_target"]).to eq([expected_output_target])
    end

    it "accepts a CloudInput builder in jobs.add_input" do
      client, sender = make_client
      sender.add_json(200, "id" => "in-1", "type" => "cloud", "source" => "ftp")

      client.jobs.add_input(
        "job-1",
        Api2Convert::Model::CloudInput.ftp(
          host: "ftp.example.com", file: "in/a.png", username: "u", password: "p"
        )
      )

      body = sender.requests.first.json
      expect(body["type"]).to eq("cloud")
      expect(body["source"]).to eq("ftp")
      expect(body["parameters"]).to eq("host" => "ftp.example.com", "file" => "in/a.png")
      expect(body["credentials"]).to eq("username" => "u", "password" => "p")
    end
  end

  # ---- Fixture 2: read hydration (a GET /jobs/{id} response) -----------------

  describe "fixture 2 — read hydration" do
    it "hydrates a cloud input and an output target with raw strings" do
      job = Api2Convert::Model::Job.from_hash(
        "id" => "job-1",
        "status" => { "code" => "completed" },
        "input" => [{
          "id" => "in-1", "type" => "cloud", "source" => "amazons3", "status" => "ready",
          "parameters" => { "bucket" => "my-bucket", "file" => "in/photo.png" },
          "credentials" => {}
        }],
        "conversion" => [{
          "id" => "c-1", "target" => "jpg",
          "output_target" => [{
            "type" => "ftp",
            "parameters" => { "host" => "ftp.example.com", "file" => "/out/photo.jpg" },
            "credentials" => {}, "status" => "uploading"
          }]
        }]
      )

      # 1) input source is a RAW string; parameters surface.
      input = job.input.first
      expect(input.source).to eq("amazons3")
      expect(input.status).to eq("ready")
      expect(input.parameters).to eq("bucket" => "my-bucket", "file" => "in/photo.png")

      # 2) output target status/parameters/type surface.
      out = job.conversion.first.output_targets.first
      expect(out.type).to eq("ftp")
      expect(out.status).to eq("uploading")
      expect(out.parameters).to eq("host" => "ftp.example.com", "file" => "/out/photo.jpg")

      # 3) credentials are never surfaced (API returns them empty; SDK doesn't hydrate).
      expect(out.credentials).to eq({})
    end

    it "round-trips an unknown provider string without raising" do
      job = Api2Convert::Model::Job.from_hash(
        "id" => "job-1",
        "status" => { "code" => "completed" },
        "input" => [{ "id" => "in-1", "type" => "cloud", "source" => "r2", "status" => "ready" }],
        "conversion" => [{
          "target" => "jpg",
          "output_target" => [{ "type" => "r2", "status" => "waiting" }]
        }]
      )

      expect(job.input.first.source).to eq("r2")
      expect(job.conversion.first.output_targets.first.type).to eq("r2")
      expect(job.conversion.first.output_targets.first.status).to eq("waiting")
    end
  end

  # ---- Unit: the new value types ---------------------------------------------

  describe "cloud value types" do
    it "exposes the six-value provider vocabulary in canonical order" do
      expect(Api2Convert::CloudProvider::ALL).to eq(
        %w[amazons3 azure ftp gdrive googlecloud youtube]
      )
    end

    it "carries each provider's required keys verbatim (flat/lowercase)" do
      expect(
        Api2Convert::Model::CloudInput.azure(
          container: "c", file: "f", accountname: "n", accountkey: "k"
        ).to_h
      ).to eq(
        "type" => "cloud", "source" => "azure",
        "parameters" => { "container" => "c", "file" => "f" },
        "credentials" => { "accountname" => "n", "accountkey" => "k" }
      )

      expect(
        Api2Convert::Model::CloudInput.google_cloud(
          projectid: "p", bucket: "b", file: "f", keyfile: "kf"
        ).to_h
      ).to eq(
        "type" => "cloud", "source" => "googlecloud",
        "parameters" => { "projectid" => "p", "bucket" => "b", "file" => "f" },
        "credentials" => { "keyfile" => "kf" }
      )
    end

    it "merges forward-compat keys through the trailing maps and generic escape hatch" do
      input = Api2Convert::Model::CloudInput.amazon_s3(
        bucket: "b", file: "f", accesskeyid: "id", secretaccesskey: "sec",
        parameters: { "region" => "eu" }, credentials: { "sessiontoken" => "t" }
      )
      expect(input.parameters).to eq("bucket" => "b", "file" => "f", "region" => "eu")
      expect(input.credentials).to eq(
        "accesskeyid" => "id", "secretaccesskey" => "sec", "sessiontoken" => "t"
      )

      generic = Api2Convert::Model::CloudInput.of("r2", parameters: { "bucket" => "b" })
      expect(generic.to_h["source"]).to eq("r2")
    end

    it "omits status on serialize but hydrates it on read" do
      created = Api2Convert::Model::OutputTarget.new(
        type: "ftp", parameters: { "host" => "h" }, credentials: { "username" => "u" },
        status: "completed"
      )
      expect(created.to_h).not_to have_key("status")

      read = Api2Convert::Model::OutputTarget.from_hash(
        "type" => "ftp", "parameters" => { "host" => "h" }, "status" => "completed"
      )
      expect(read.status).to eq("completed")
      expect(read.credentials).to eq({})
    end

    it "freezes the value objects" do
      expect(Api2Convert::Model::CloudInput.ftp(host: "h", file: "f", username: "u", password: "p"))
        .to be_frozen
      expect(Api2Convert::Model::OutputTarget.new(type: "ftp")).to be_frozen
    end
  end
end
