# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "openssl"

# These specs pin the mid-stream failure contract of the real sender. A download
# body is streamed straight to disk, so a failure AFTER bytes have flowed must be
# surfaced as a non-retryable NetworkError — if it escaped as a plain transport
# error the Transport retry loop would re-stream the whole body and append it to
# the partial file, silently corrupting the download.
RSpec.describe Api2Convert::Http::NetHttpSender do
  it "keeps STREAM_ERRORS a superset of Transport::TRANSPORT_ERRORS" do
    missing = Api2Convert::Http::Transport::TRANSPORT_ERRORS -
              Api2Convert::Http::NetHttpSender::STREAM_ERRORS
    # Any retryable transport error not intercepted mid-stream would be retried
    # and corrupt a partially-written download (e.g. OpenSSL::SSL::SSLError on a
    # truncated TLS body).
    expect(missing).to be_empty
  end

  it "wraps a mid-stream TLS truncation as a non-retryable NetworkError" do
    sender = described_class.new
    sink = StringIO.new

    res = Object.new
    res.define_singleton_method(:read_body) do |&block|
      block.call("PARTIAL-BYTES")
      raise OpenSSL::SSL::SSLError, "SSL_read: unexpected eof while reading"
    end

    expect { sender.send(:stream_body, res, sink) }
      .to raise_error(Api2Convert::NetworkError, /Download stream failed/)
  end
end
