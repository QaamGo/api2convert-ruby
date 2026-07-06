# frozen_string_literal: true

module Api2Convert
  module Support
    # Redaction helpers for `#inspect` / `#to_s`.
    #
    # Without these, `p client`, a `config.inspect` in a log line, or an object
    # dumped in a backtrace would print `@api_key` / `@download_password` in
    # cleartext. Every object that holds a secret overrides `#inspect` to route the
    # secret through {mask}. Internal helper, not part of the public API.
    module Secret
      module_function

      # Mask a secret for display. A `nil` renders as `nil`; a sufficiently long
      # value keeps only its last 4 characters (so it stays recognizable in a log)
      # with the rest hidden; a short value collapses to `[FILTERED]`.
      def mask(value)
        return "nil" if value.nil?

        str = value.to_s
        return "[FILTERED]" if str.length < 8

        "[FILTERED:...#{str[-4..-1]}]"
      end
    end
  end
end
