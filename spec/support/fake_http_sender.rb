# frozen_string_literal: true

require "json"

# An in-memory {Api2Convert::Http::HttpSender} for offline unit tests: it records
# every request it is handed and replies with FIFO-queued canned responses (or
# raises a queued transport error). No network, no sleeping.
class FakeHttpSender
  # A recorded request, with case-insensitive header access for assertions.
  class RecordedRequest
    attr_reader :method, :url, :headers, :body, :follow_redirects

    def initialize(method:, url:, headers:, body:, follow_redirects:)
      @method = method
      @url = url
      @headers = headers
      @body = body
      @follow_redirects = follow_redirects
    end

    def header(name)
      key = @headers.keys.find { |k| k.to_s.downcase == name.to_s.downcase }
      key.nil? ? nil : @headers[key]
    end

    def json
      return nil if @body.nil? || @body.empty?

      JSON.parse(@body)
    end

    def query
      index = @url.index("?")
      index.nil? ? "" : @url[(index + 1)..-1]
    end
  end

  attr_reader :requests

  def initialize
    @queue = []
    @requests = []
  end

  def add_json(status, data, headers = {})
    body = data.is_a?(String) ? data : JSON.generate(data)
    @queue << { status: status, body: body, headers: headers.merge("content-type" => "application/json") }
    self
  end

  def add_raw(status, body, headers = {})
    @queue << { status: status, body: body, headers: headers }
    self
  end

  # Queue a transport-level failure (e.g. SocketError.new) for the next request.
  def add_error(exception)
    @queue << { error: exception }
    self
  end

  def last
    @requests.last
  end

  def call(request)
    body = request.body
    body = request.body_stream.read if body.nil? && request.body_stream
    @requests << RecordedRequest.new(
      method: request.method, url: request.url,
      headers: request.headers.dup, body: body,
      follow_redirects: request.follow_redirects
    )

    raise "FakeHttpSender: no queued response for #{request.method} #{request.url}" if @queue.empty?

    entry = @queue.shift
    raise entry[:error] if entry[:error]

    normalized = {}
    (entry[:headers] || {}).each { |key, value| normalized[key.to_s.downcase] = value }
    Api2Convert::Http::Response.new(entry[:status], normalized, entry[:body] || "", "")
  end
end
