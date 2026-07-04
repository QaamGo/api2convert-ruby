# frozen_string_literal: true

module Api2Convert
  # The typed exception hierarchy.
  #
  # Every failure raised by the SDK descends from {Error}. HTTP error responses
  # (status >= 400) map to {ApiError} and its subclasses; transport failures,
  # conversion failures, poll timeouts and webhook verification failures descend
  # directly from the base.
  #
  # The class names use Ruby's `...Error` convention; they map 1:1 to the PHP
  # SDK's `...Exception` classes.
  class Error < StandardError; end

  # An HTTP error response (status >= 400).
  #
  # Used directly for a 4xx with no more specific subclass; specific statuses map
  # to the dedicated subclasses below.
  class ApiError < Error
    # @return [Integer] the HTTP status code.
    attr_reader :status_code
    # @return [String, nil] the `X-Request-Id` response header, if any. Quote it
    #   in support requests.
    attr_reader :request_id
    # @return [Hash] the decoded JSON error body, or `{}` when absent/unparseable.
    attr_reader :body

    def initialize(message, status_code: 0, request_id: nil, body: nil)
      super(message)
      @status_code = status_code
      @request_id = request_id
      @body = body || {}
    end
  end

  # The API key is missing, invalid or not permitted (HTTP 401 / 403).
  class AuthenticationError < ApiError; end

  # The account has no remaining quota/credit (HTTP 402).
  class PaymentRequiredError < ApiError; end

  # The requested resource does not exist (HTTP 404).
  class NotFoundError < ApiError; end

  # The request was rejected as invalid, e.g. an unknown target (HTTP 400 / 422).
  class ValidationError < ApiError; end

  # Too many requests (HTTP 429), raised only once auto-retries are exhausted.
  class RateLimitError < ApiError
    # @return [Integer, nil] seconds to wait before retrying, parsed from the
    #   `Retry-After` header (raw, uncapped).
    attr_reader :retry_after

    def initialize(message, status_code: 429, request_id: nil, body: nil, retry_after: nil)
      super(message, status_code: status_code, request_id: request_id, body: body)
      @retry_after = retry_after
    end
  end

  # A server-side error (HTTP >= 500), raised once auto-retries are exhausted.
  class ServerError < ApiError; end

  # A request did not yield a usable response.
  #
  # Raised for a transport-level failure (DNS/connection/TLS/read) once idempotent
  # retries are exhausted, or for a 2xx response whose body is not valid JSON.
  class NetworkError < Error; end

  # A job reached the `failed` (or `canceled`) status.
  #
  # The originating {Model::Job} is attached so you can inspect its errors and
  # warnings.
  class ConversionFailedError < Error
    # @return [Model::Job] the failed job.
    attr_reader :job

    def initialize(job, message = nil)
      @job = job
      super(message.nil? ? self.class.build_message(job) : message)
    end

    # @return [Array<Model::JobMessage>] the failed job's errors (may be empty if
    #   the API gave no detail).
    def errors
      @job.errors
    end

    def self.build_message(job)
      first = job.errors.first
      unless first.nil?
        code = first.code.nil? ? "" : " (code #{first.code})"
        return "Conversion failed: #{first.message}#{code}"
      end
      info = job.status.info
      info.nil? ? "Conversion failed." : "Conversion failed: #{info}"
    end
  end

  # A job did not reach a terminal status within the configured poll timeout.
  #
  # The job is still running server-side — re-fetch it later with
  # `client.jobs.get(job.id)`. (Maps to the PHP SDK's `TimeoutException`; named to
  # avoid shadowing Ruby's `Timeout::Error`.)
  class ConversionTimeoutError < Error
    # @return [Model::Job] the job that was still running when the wait timed out.
    attr_reader :job

    def initialize(job, timeout_seconds)
      @job = job
      super(
        "Timed out after #{timeout_seconds}s waiting for job #{job.id} to finish " \
        "(last status: #{job.status.code})."
      )
    end
  end

  # A webhook payload could not be verified against the provided signature/secret.
  #
  # Treat this as a security event: do not trust or process the payload.
  class SignatureVerificationError < Error; end
end
