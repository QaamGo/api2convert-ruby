# frozen_string_literal: true

require "tmpdir"

RSpec.describe Api2Convert::Result do
  def output(attrs = {})
    Api2Convert::Model::OutputFile.from_hash({ "uri" => "https://dl.example/x" }.merge(attrs))
  end

  describe Api2Convert::Result::FileDownload do
    it "returns the download URL, contents and saves to a file" do
      client, sender = make_client
      dl = client.download(output("filename" => "out.pdf"))
      expect(dl.url).to eq("https://dl.example/x")

      sender.add_raw(200, "PDFBYTES")
      expect(dl.contents).to eq("PDFBYTES")

      sender.add_raw(200, "PDFBYTES")
      Dir.mktmpdir do |dir|
        path = dl.save(File.join(dir, "result.pdf"))
        expect(File.binread(path)).to eq("PDFBYTES")
      end
    end

    it "streams the body straight to disk on save (the download call buffers nothing)" do
      client, sender = make_client
      sender.add_raw(200, "STREAMED-TO-DISK")
      Dir.mktmpdir do |dir|
        target = File.join(dir, "out.bin")
        expect(client.download(output).save(target)).to eq(target)
        expect(File.binread(target)).to eq("STREAMED-TO-DISK")
      end
      # The transport streamed to the sink, so the Response handed back was empty.
      expect(sender.last.follow_redirects).to be(true)
    end

    it "removes the partial file when the download fails mid-stream" do
      client, sender = make_client
      sender.add_stream_error(Api2Convert::NetworkError.new("stream died"), "PARTIAL-BYTES")
      Dir.mktmpdir do |dir|
        target = File.join(dir, "broken.bin")
        expect { client.download(output).save(target) }
          .to raise_error(Api2Convert::NetworkError, /stream died/)
        expect(File.exist?(target)).to be(false)
        # The sibling temp file must be cleaned up too (no `.part` litter left behind).
        expect(Dir.children(dir)).to be_empty
      end
    end

    it "types a mid-stream read failure as a NetworkError, not a filesystem error" do
      client, sender = make_client
      sender.add_stream_error(Api2Convert::NetworkError.new("stream died"), "PARTIAL-BYTES")
      Dir.mktmpdir do |dir|
        # A read fault part-way through streaming is a transport error — never
        # mislabeled "Could not write file" — so a retrying caller can tell the two apart.
        expect { client.download(output).save(File.join(dir, "out.bin")) }
          .to raise_error(Api2Convert::NetworkError)
      end
    end

    it "leaves a pre-existing complete file untouched when the download fails mid-stream" do
      # Temp-file + atomic rename means a mid-stream failure must not truncate or
      # destroy a previously-complete file at the target path.
      client, sender = make_client
      sender.add_stream_error(Api2Convert::NetworkError.new("stream died"), "PARTIAL-BYTES")
      Dir.mktmpdir do |dir|
        target = File.join(dir, "result.pdf")
        File.binwrite(target, "PREEXISTING COMPLETE FILE")
        expect { client.download(output).save(target) }
          .to raise_error(Api2Convert::NetworkError, /stream died/)
        expect(File.binread(target)).to eq("PREEXISTING COMPLETE FILE")
      end
    end

    it "keeps the API filename when saving to a directory" do
      client, sender = make_client
      sender.add_raw(200, "DATA")
      Dir.mktmpdir do |dir|
        path = client.download(output("filename" => "report.pdf")).save(dir)
        expect(path).to eq(File.join(dir, "report.pdf"))
      end
    end

    it "falls back to the output id when the API filename reduces to nothing usable" do
      client, sender = make_client
      sender.add_raw(200, "DATA")
      Dir.mktmpdir do |dir|
        path = client.download(output("filename" => "/", "id" => "out-9")).save(dir)
        expect(path).to eq(File.join(dir, "out-9"))
      end
    end

    it "sends a passwordless download WITH redirects followed and no password header" do
      client, sender = make_client
      sender.add_raw(200, "DATA")
      client.download(output).contents
      expect(sender.last.follow_redirects).to be(true)
      expect(sender.last.header("X-Api2convert-Download-Password")).to be_nil
    end

    it "sends a password-protected download WITHOUT following redirects" do
      client, sender = make_client
      sender.add_raw(200, "DATA")
      client.download(output, "s3cret").contents
      expect(sender.last.follow_redirects).to be(false)
      expect(sender.last.header("X-Api2convert-Download-Password")).to eq("s3cret")
    end
  end

  describe Api2Convert::Result::ConversionResult do
    def completed_job
      Api2Convert::Model::Job.from_hash(
        "id" => "j",
        "status" => { "code" => "completed" },
        "output" => [
          { "uri" => "https://dl/one", "filename" => "one.pdf" },
          { "uri" => "https://dl/two", "filename" => "two.pdf" }
        ]
      )
    end

    it "selects the first output by default and exposes all outputs" do
      client, = make_client
      result = Api2Convert::Result::ConversionResult.new(completed_job, client_transport(client))
      expect(result.url).to eq("https://dl/one")
      expect(result.outputs.length).to eq(2)
    end

    it "raises when the requested output index is out of range" do
      client, = make_client
      result = Api2Convert::Result::ConversionResult.new(completed_job, client_transport(client), 5)
      expect { result.output }.to raise_error(Api2Convert::Error, /no output files/)
    end

    it "remembers a download password from conversion time and applies it automatically" do
      client, sender = make_client
      result = Api2Convert::Result::ConversionResult.new(completed_job, client_transport(client), 0, "pw")
      sender.add_raw(200, "DATA")
      result.contents
      expect(sender.last.header("X-Api2convert-Download-Password")).to eq("pw")

      sender.add_raw(200, "DATA")
      result.contents("override")
      expect(sender.last.header("X-Api2convert-Download-Password")).to eq("override")
    end
  end

  # Reach the client's private transport for building result objects directly.
  def client_transport(client)
    client.instance_variable_get(:@transport)
  end
end
