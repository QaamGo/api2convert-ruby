# frozen_string_literal: true

# Helpers mixed into every example group.
module ClientHelper
  # A client wired to a {FakeHttpSender} and a recording sleeper (no network, no
  # real sleeping, deterministic jitter). Returns `[client, sender, sleeps]`.
  def make_client(options = {}, api_key = "test-key")
    sender = FakeHttpSender.new
    sleeps = []
    client = Api2Convert::Client.new(
      api_key,
      http_sender: sender,
      sleeper: ->(seconds) { sleeps << seconds },
      rng: -> { 0.0 }, **options
    )
    [client, sender, sleeps]
  end

  # A client backed by the REAL Net::HTTP sender (for the security suite's
  # loopback-server redirect proofs). No retries, no real sleeping.
  def real_client(base_url: nil, api_key: "secret-key", max_retries: 0)
    Api2Convert::Client.new(
      api_key,
      base_url: base_url,
      max_retries: max_retries,
      timeout: 5,
      sleeper: ->(_seconds) {},
      rng: -> { 0.0 }
    )
  end
end

RSpec.configure do |config|
  config.include ClientHelper
end
