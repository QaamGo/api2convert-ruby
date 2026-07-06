# frozen_string_literal: true

RSpec.describe "API resources" do
  describe Api2Convert::Resource::Jobs do
    it "lists jobs with a page/status query" do
      client, sender = make_client
      sender.add_json(200, [{ "id" => "a", "status" => { "code" => "completed" } },
                            "junk",
                            { "id" => "b", "status" => { "code" => "failed" } }])
      jobs = client.jobs.list("completed", 2)
      expect(jobs.map(&:id)).to eq(%w[a b]) # non-object rows are skipped
      expect(sender.last.query).to include("page=2", "status=completed")
    end

    it "starts a staged job with process:true" do
      client, sender = make_client
      sender.add_json(200, "id" => "j", "status" => { "code" => "processing" })
      client.jobs.start("j")
      expect(sender.last.method).to eq("PATCH")
      expect(sender.last.url).to end_with("/jobs/j")
      expect(sender.last.json).to eq("process" => true)
    end

    it "adds a remote input" do
      client, sender = make_client
      sender.add_json(200, "id" => "in", "type" => "remote", "source" => "https://x/y")
      input = client.jobs.add_input("j", "type" => "remote", "source" => "https://x/y")
      expect(sender.last.url).to end_with("/jobs/j/input")
      expect(input.type).to eq("remote")
    end

    it "cancels a job with DELETE" do
      client, sender = make_client
      sender.add_raw(204, "")
      expect(client.jobs.cancel("j")).to be_nil
      expect(sender.last.method).to eq("DELETE")
    end

    it "lists outputs" do
      client, sender = make_client
      sender.add_json(200, [{ "uri" => "https://dl/1" }, { "uri" => "https://dl/2" }])
      outputs = client.jobs.outputs("j")
      expect(outputs.map(&:uri)).to eq(%w[https://dl/1 https://dl/2])
    end
  end

  describe Api2Convert::Resource::Conversions do
    it "returns the options of the first matching conversion" do
      client, sender = make_client
      sender.add_json(200, [{ "target" => "mp4", "options" => { "video_codec" => {} } }])
      expect(client.conversions.options("mp4", "video")).to eq("video_codec" => {})
      expect(sender.last.query).to include("target=mp4", "category=video")
    end

    it "returns an empty hash when no conversion matches" do
      client, sender = make_client
      sender.add_json(200, [])
      expect(client.conversions.options("nope")).to eq({})
    end
  end

  describe Api2Convert::Resource::Presets do
    it "creates and gets a preset" do
      client, sender = make_client
      sender.add_json(200, "id" => "p1", "name" => "my-preset", "target" => "pdf")
      preset = client.presets.create("name" => "my-preset", "target" => "pdf")
      expect(preset.name).to eq("my-preset")
      expect(sender.last.method).to eq("POST")

      sender.add_json(200, "id" => "p1", "name" => "my-preset")
      expect(client.presets.get("p1").id).to eq("p1")
    end

    it "filters the preset list query" do
      client, sender = make_client
      sender.add_json(200, [])
      client.presets.list(category: "image", target: "png")
      expect(sender.last.query).to include("category=image", "target=png")
    end
  end

  describe Api2Convert::Resource::Stats do
    it "builds the day stats path" do
      client, sender = make_client
      sender.add_json(200, "conversions" => 5)
      client.stats.day("2026-07-04")
      expect(sender.last.url).to end_with("/stats/day/2026-07-04/all")
    end
  end

  describe Api2Convert::Resource::Contracts do
    it "gets the contracts resource" do
      client, sender = make_client
      sender.add_json(200, "contracts" => [])
      client.contracts.get
      expect(sender.last.url).to end_with("/contracts")
    end
  end

  describe "path-segment encoding" do
    it "percent-encodes a job id carrying reserved characters so it cannot escape its segment" do
      client, sender = make_client
      sender.add_json(200, "id" => "x", "status" => { "code" => "completed" })
      client.jobs.get("a/b?c#d e")
      path = sender.last.url.split("?").first
      expect(path).to end_with("/jobs/a%2Fb%3Fc%23d%20e")
    end

    it "encodes a preset id in the path" do
      client, sender = make_client
      sender.add_json(200, "id" => "p", "name" => "n")
      client.presets.get("../../contracts")
      expect(sender.last.url).to end_with("/presets/..%2F..%2Fcontracts")
    end

    it "encodes both stats path segments (date and filter)" do
      client, sender = make_client
      sender.add_json(200, {})
      client.stats.day("2026/07", "team a/b")
      expect(sender.last.url).to end_with("/stats/day/2026%2F07/team%20a%2Fb")
    end
  end
end
