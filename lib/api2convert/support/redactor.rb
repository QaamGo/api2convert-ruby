# frozen_string_literal: true

module Api2Convert
  module Support
    # Credential redaction for cloud connectors.
    #
    # Cloud `credentials` ride in the plaintext request body, so they must never
    # surface where a value object or an SDK-emitted string could leak them. This
    # helper centralizes the masks the contract mandates:
    #
    # - the **whole `credentials` object** collapses to {MARKER} on every
    #   object-inspection path (`#inspect` / `#to_s`);
    # - any `parameters` leaf whose key contains a sensitive token
    #   ({SENSITIVE_SUBSTRINGS}, case-insensitive substring) collapses to {MARKER};
    # - the decoded error body is deep-walked ({redact_body}) as belt-and-
    #   suspenders — the API only ever echoes field *names*, never a credential
    #   *value*, but a future server/proxy change must not be able to leak one.
    #
    # Internal helper, not part of the public API.
    module Redactor
      module_function

      # The fixed, fleet-wide redaction marker (D9).
      MARKER = "[REDACTED]"

      # Case-insensitive substrings that mark a key as carrying a secret. A key
      # containing any of these has its whole value masked.
      SENSITIVE_SUBSTRINGS = %w[
        token password passwd secret key keyfile
        credential passphrase sas sig signature
      ].freeze

      # Whether a key name marks its value as sensitive (case-insensitive
      # substring match). Accepts String or Symbol keys.
      def sensitive_key?(key)
        lower = key.to_s.downcase
        SENSITIVE_SUBSTRINGS.any? { |needle| lower.include?(needle) }
      end

      # Mask sensitive leaves of a `parameters` map: any key matching
      # {sensitive_key?} has its value replaced by {MARKER}; nested Hashes are
      # walked recursively. Non-secret keys (`bucket`, `host`, `file`,
      # `container`, `projectid`, …) are left untouched.
      def parameters(params)
        return params unless params.is_a?(Hash)

        params.each_with_object({}) do |(key, value), out|
          out[key] =
            if sensitive_key?(key)
              MARKER
            elsif value.is_a?(Hash)
              parameters(value)
            else
              value
            end
        end
      end

      # Deep-walk a decoded error body and mask the value of every sensitive key
      # (including a flattened/dotted key like
      # `input.0.credentials.secretaccesskey`) to {MARKER}. Nested Hashes and
      # Arrays are walked; scalars pass through.
      def redact_body(body)
        case body
        when Hash
          body.each_with_object({}) do |(key, value), out|
            out[key] = sensitive_key?(key) ? MARKER : redact_body(value)
          end
        when Array
          body.map { |value| redact_body(value) }
        else
          body
        end
      end
    end
  end
end
