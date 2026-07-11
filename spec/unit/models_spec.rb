# frozen_string_literal: true

RSpec.describe "model hydration" do
  describe Api2Convert::Model::Job do
    it "hydrates a full job and exposes typed sub-models" do
      job = described_class.from_hash(
        "id" => "job-1",
        "status" => { "code" => "completed", "info" => "done" },
        "token" => "tok",
        "server" => "https://up.example",
        "conversion" => [{ "target" => "pdf", "options" => { "pdf_a" => true } }],
        "output" => [{ "uri" => "https://dl/x", "filename" => "out.pdf", "size" => 42 }],
        "errors" => [{ "code" => 4, "message" => "bad" }]
      )
      expect(job.id).to eq("job-1")
      expect(job.status.code).to eq("completed")
      expect(job.status.info).to eq("done")
      expect(job.conversion.first.target).to eq("pdf")
      expect(job.output.first.size).to eq(42)
      expect(job.errors.first.code).to eq(4)
      expect(job).to be_completed
      expect(job).to be_terminal
      expect(job).to be_frozen
      expect(job.raw["token"]).to eq("tok")
    end

    it "never raises on a surprising payload and defaults everything" do
      job = described_class.from_hash({})
      expect(job.id).to eq("")
      expect(job.status.code).to eq("")
      expect(job.token).to be_nil
      expect(job.conversion).to eq([])
      expect(job).not_to be_terminal
    end

    it "tolerates wrong-typed fields and skips non-object list entries" do
      job = described_class.from_hash(
        "id" => 123, "status" => "nope",
        "output" => ["junk", { "uri" => "https://dl/y" }, nil]
      )
      expect(job.id).to eq("") # a non-string id falls back to ""
      expect(job.status.code).to eq("")
      expect(job.output.length).to eq(1)
      expect(job.output.first.uri).to eq("https://dl/y")
    end

    it "treats an unknown status code as non-terminal" do
      job = described_class.from_hash("status" => { "code" => "quantum" })
      expect(job).not_to be_terminal
      expect(job).not_to be_completed
    end

    it "reports failed and canceled" do
      expect(described_class.from_hash("status" => { "code" => "failed" })).to be_failed
      expect(described_class.from_hash("status" => { "code" => "canceled" })).to be_canceled
      expect(described_class.from_hash("status" => { "code" => "failed" })).to be_terminal
    end
  end

  describe Api2Convert::Support::Data do
    it "coerces numeric strings/floats to int but rejects booleans" do
      expect(described_class.nullable_int("3.9")).to eq(3)
      expect(described_class.nullable_int(7)).to eq(7)
      expect(described_class.nullable_int(true)).to be_nil
      expect(described_class.nullable_int("nope")).to be_nil
    end

    it "preserves arbitrarily large integers without overflow or precision loss" do
      # Ruby integers are arbitrary-precision, so a huge file size hydrates exactly
      # (no fixed-width overflow to wrap or saturate against — unlike Java/.NET).
      expect(described_class.nullable_int(10**19)).to eq(10_000_000_000_000_000_000)
      expect(described_class.nullable_int("9223372036854775808")).to eq(9_223_372_036_854_775_808)
    end

    it "returns nil (never raises) for a non-finite numeric string" do
      # A numeric string that overflows Float to +/-Infinity ("1e400") must fall back
      # to nil, not crash with FloatDomainError — the helper never raises on a payload.
      expect(described_class.nullable_int("1e400")).to be_nil
      expect(described_class.nullable_int("-1e400")).to be_nil
      expect(described_class.nullable_int(Float::INFINITY)).to be_nil
      expect(described_class.nullable_int(Float::NAN)).to be_nil
    end

    it "reduces a JSON object to its values in as_list" do
      expect(described_class.as_list("a" => 1, "b" => 2)).to contain_exactly(1, 2)
      expect(described_class.as_list("scalar")).to eq([])
    end
  end
end
