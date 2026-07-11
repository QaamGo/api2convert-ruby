# frozen_string_literal: true

require "socket"

# A tiny real HTTP server on 127.0.0.1, for the independent security suite. It is
# the Ruby analog of the Node.js loopback helper / Java `SecurityTest`'s
# `com.sun.net.httpserver` servers: only a real cross-host redirect between real
# servers can prove the transport does not forward an `X-Api2convert-*` secret header to
# the redirect target (a mocked sender would short-circuit the redirect entirely).
#
# The block handler is called with the received (downcased) headers and returns a
# response spec: `{ status:, body:, headers: }`. Every request bumps a hit counter
# and its headers are recorded first.
class LoopbackServer
  REASONS = {
    200 => "OK", 301 => "Moved Permanently", 302 => "Found",
    303 => "See Other", 307 => "Temporary Redirect", 308 => "Permanent Redirect",
    400 => "Bad Request", 404 => "Not Found", 500 => "Internal Server Error"
  }.freeze

  attr_reader :port

  def initialize(&handler)
    @handler = handler
    @hits = 0
    @headers = []
    @mutex = Mutex.new
    @closed = false
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @thread = Thread.new { serve }
  end

  def url
    "http://127.0.0.1:#{@port}"
  end

  def hits
    @mutex.synchronize { @hits }
  end

  # Every request's headers, in order (each a downcased-key Hash).
  def headers_received
    @mutex.synchronize { @headers.map(&:dup) }
  end

  def close
    @closed = true
    begin
      @server.close
    rescue StandardError
      nil
    end
    begin
      @thread.join(1)
    rescue StandardError
      nil
    end
  end

  private

  def serve
    until @closed
      begin
        client = @server.accept
      rescue IOError, Errno::EBADF, Errno::ECONNABORTED
        break
      end
      handle_client(client)
    end
  end

  def handle_client(client)
    request_line = client.gets
    return if request_line.nil?

    headers = {}
    while (line = client.gets)
      break if ["\r\n", "\n"].include?(line)

      key, _sep, value = line.partition(":")
      headers[key.strip.downcase] = value.strip
    end

    length = headers["content-length"].to_i
    client.read(length) if length.positive?

    @mutex.synchronize do
      @hits += 1
      @headers << headers
    end

    spec = @handler ? @handler.call(headers) : {}
    client.write(build_response(spec || {}))
  rescue StandardError
    # A client that closes the connection abruptly (e.g. a test asserting the
    # request never happens) must not crash the accept loop.
    nil
  ensure
    begin
      client&.close
    rescue StandardError
      nil
    end
  end

  def build_response(spec)
    status = spec[:status] || 200
    body = (spec[:body] || "").to_s
    reason = REASONS[status] || "OK"
    lines = ["HTTP/1.1 #{status} #{reason}", "Content-Length: #{body.bytesize}"]
    (spec[:headers] || {}).each { |key, value| lines << "#{key}: #{value}" }
    lines << "Connection: close"
    "#{lines.join("\r\n")}\r\n\r\n#{body}"
  end
end
