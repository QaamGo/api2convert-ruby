# frozen_string_literal: true

require "json"
require "openssl"

module Api2Convert
  module Webhook
    # Webhook callback verification and parsing.
    #
    # Pass the **raw** request body (the exact string received) so signature
    # verification is byte-exact. Verification uses HMAC-SHA256 and matches the
    # server's signed-webhooks scheme; until signed webhooks are enabled on your
    # account no signature is sent — use {#parse} then, or call {#construct_event}
    # with an empty secret to skip verification.
    class Verifier
      # Verify the signature (when a secret is given) and return the typed event.
      #
      # +payload+ must be the raw request body. +signature+ is the value of the
      # signature header (`X-Oc-Signature`). Pass an empty +secret+ to skip
      # verification. Raises {SignatureVerificationError} when the signature is
      # missing or does not match.
      def construct_event(payload, signature, secret)
        unless secret.nil? || secret == ""
          if signature.nil? || signature == ""
            raise SignatureVerificationError, "Missing webhook signature header."
          end

          expected = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, to_bytes(payload))
          unless secure_compare(expected, signature)
            raise SignatureVerificationError, "Webhook signature verification failed."
          end
        end

        parse(payload)
      end

      # Parse a callback body into a typed event WITHOUT verifying a signature.
      # Only use this when signed webhooks are not yet enabled for your account.
      def parse(payload)
        begin
          decoded = JSON.parse(to_bytes(payload))
        rescue JSON::ParserError => e
          raise SignatureVerificationError, "Webhook payload is not valid JSON: #{e.message}"
        end
        raise SignatureVerificationError, "Webhook payload is not a JSON object." unless decoded.is_a?(Hash)

        Event.from_hash(decoded)
      end

      private

      def to_bytes(payload)
        payload.is_a?(String) ? payload : payload.to_s
      end

      # Constant-time comparison, guarding the length check first. Uses OpenSSL's
      # fixed-length compare when available (Ruby 2.6+); otherwise a portable
      # branch-free fallback so old Rubies stay constant-time too.
      def secure_compare(expected, actual)
        a = expected.to_s.b
        b = actual.to_s.b
        return false unless a.bytesize == b.bytesize

        if OpenSSL.respond_to?(:fixed_length_secure_compare)
          OpenSSL.fixed_length_secure_compare(a, b)
        else
          result = 0
          a.bytesize.times { |i| result |= a.getbyte(i) ^ b.getbyte(i) }
          result.zero?
        end
      end
    end
  end
end
