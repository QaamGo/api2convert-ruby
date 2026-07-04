# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Api2Convert::Upload::FileUploader do
  def staged_job
    Api2Convert::Model::Job.from_hash(
      "id" => "job-9",
      "status" => { "code" => "incomplete" },
      "token" => "tok-abc",
      "server" => "https://up.example.test"
    )
  end

  it "posts to the per-job upload server and authenticates with the job token, never the account key" do
    client, sender = make_client
    sender.add_json(200, "id" => "in-1", "type" => "upload")

    input = client.jobs.upload(staged_job, StringIO.new("hello world"))

    req = sender.last
    expect(req.method).to eq("POST")
    expect(req.url).to eq("https://up.example.test/upload-file/job-9")
    expect(req.header("X-Oc-Token")).to eq("tok-abc")
    expect(req.header("X-Oc-Api-Key")).to be_nil
    expect(req.header("Content-Type")).to start_with("multipart/form-data; boundary=")
    expect(req.follow_redirects).to be(false)
    expect(req.body).to include("hello world")
    expect(req.body).to include('name="file"')
    expect(input.type).to eq("upload")
  end

  it "uses the file's basename as the multipart filename for a path source" do
    client, sender = make_client
    sender.add_json(200, "id" => "in-2", "type" => "upload")

    Dir.mktmpdir do |dir|
      path = File.join(dir, "report.docx")
      File.binwrite(path, "DOCXBYTES")
      client.jobs.upload(staged_job, path)
      expect(sender.last.body).to include('filename="report.docx"')
      expect(sender.last.body).to include("DOCXBYTES")
    end
  end

  it "honors an explicit filename override" do
    client, sender = make_client
    sender.add_json(200, "id" => "in-3", "type" => "upload")
    client.jobs.upload(staged_job, StringIO.new("x"), "custom.bin")
    expect(sender.last.body).to include('filename="custom.bin"')
  end

  it "raises when the job has no upload server/token" do
    client, = make_client
    job = Api2Convert::Model::Job.from_hash("id" => "j", "status" => { "code" => "created" })
    expect { client.jobs.upload(job, StringIO.new("x")) }
      .to raise_error(Api2Convert::Error, %r{no upload server/token})
  end

  it "raises a clear error when a path does not exist" do
    client, = make_client
    expect { client.jobs.upload(staged_job, "/no/such/file.xyz") }
      .to raise_error(Api2Convert::Error, /not found/)
  end
end
