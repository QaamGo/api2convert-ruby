# frozen_string_literal: true

RSpec.describe "Api2Convert::Resource::Jobs#wait" do
  it "polls until the job is completed, backing off between polls" do
    client, sender, sleeps = make_client
    sender.add_json(200, "id" => "j", "status" => { "code" => "processing" })
    sender.add_json(200, "id" => "j", "status" => { "code" => "processing" })
    sender.add_json(200, "id" => "j", "status" => { "code" => "completed" })

    job = client.jobs.wait("j")
    expect(job).to be_completed
    expect(sender.requests.length).to eq(3)
    expect(sleeps.length).to eq(2)
    # backoff grows by 1.5x from the 1.0s first interval
    expect(sleeps).to eq([1.0, 1.5])
  end

  it "raises ConversionFailedError on a failed job, carrying its errors" do
    client, sender = make_client
    sender.add_json(200, "id" => "j", "status" => { "code" => "failed" },
                         "errors" => [{ "code" => 500, "message" => "conversion blew up" }])
    expect { client.jobs.wait("j") }.to raise_error(Api2Convert::ConversionFailedError) do |error|
      expect(error.job.id).to eq("j")
      expect(error.errors.first.message).to eq("conversion blew up")
      expect(error.message).to include("conversion blew up")
    end
  end

  it "raises ConversionFailedError on a canceled job" do
    client, sender = make_client
    sender.add_json(200, "id" => "j", "status" => { "code" => "canceled" })
    expect { client.jobs.wait("j") }.to raise_error(Api2Convert::ConversionFailedError)
  end

  it "returns the failed job instead of raising when throw_on_failure is false" do
    client, sender = make_client
    sender.add_json(200, "id" => "j", "status" => { "code" => "failed" })
    job = client.jobs.wait("j", nil, false)
    expect(job).to be_failed
  end

  it "raises ConversionTimeoutError past the deadline" do
    client, sender = make_client({ poll_timeout: 0 })
    sender.add_json(200, "id" => "j", "status" => { "code" => "processing" })
    expect { client.jobs.wait("j") }.to raise_error(Api2Convert::ConversionTimeoutError) do |error|
      expect(error.job.id).to eq("j")
      expect(error.message).to include("processing")
    end
  end
end
