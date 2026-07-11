# frozen_string_literal: true

module Api2Convert
  module Support
    # Typed, null-safe accessors over decoded JSON.
    #
    # Mirrors the PHP SDK's `Support\Data` helper: model hydration stays free of
    # scattered casts and, crucially, **never raises** on a surprising payload — a
    # missing or wrong-typed field falls back to a sensible default. Internal
    # helper, not part of the public API.
    module Data
      module_function

      # Return +value+ when it is a real String, else +default+. Does not
      # stringify ints/floats/bools — only genuine strings pass through.
      def as_str(value, default = "")
        value.is_a?(String) ? value : default
      end

      def nullable_str(value)
        value.is_a?(String) ? value : nil
      end

      # Coerce numeric values to Integer (truncating toward zero), else nil.
      #
      # +true+/+false+ are rejected (they must not become 1/0). Numeric strings
      # and floats are truncated ("3.9" -> 3), matching PHP's (int) cast.
      def nullable_int(value)
        return nil if [true, false].include?(value)
        return value if value.is_a?(Integer)

        if value.is_a?(Float)
          return nil unless value.finite?

          return value.to_i
        end
        if value.is_a?(String)
          begin
            parsed = Float(value)
          rescue ArgumentError, TypeError
            return nil
          end
          # A numeric string that overflows Float to +/-Infinity (e.g. "1e400")
          # must fall back to nil, not raise: Float::INFINITY.to_i / NAN.to_i throw
          # FloatDomainError, and this helper must NEVER raise on a hostile payload
          # (mirrors the Float branch's finite? guard above).
          return nil unless parsed.finite?

          return parsed.to_i
        end
        nil
      end

      def as_bool(value, default = false)
        [true, false].include?(value) ? value : default
      end

      # Return +value+ when it is a Hash (a JSON object), else an empty Hash.
      def as_object(value)
        value.is_a?(Hash) ? value : {}
      end

      # Return a list of values: an Array passes through; a Hash is reduced to its
      # values (mirrors PHP `array_values`); anything else yields [].
      def as_list(value)
        return value if value.is_a?(Array)
        return value.values if value.is_a?(Hash)

        []
      end

      # Build a model from each Hash element of +value+; skip non-Hash elements.
      def map_objects(value)
        as_list(value).each_with_object([]) do |item, acc|
          acc << yield(item) if item.is_a?(Hash)
        end
      end

      def str_list(value)
        as_list(value).grep(String)
      end

      # Percent-encode a value for use as a single URL path segment.
      #
      # A job/preset id or a stats date/filter is interpolated into the request
      # path; a value carrying `/`, `?`, `#`, a space or any other reserved
      # character (e.g. `all/../contracts`) must be encoded so it can never break
      # out of its segment or forge a different path. Only the RFC 3986 unreserved
      # set survives; everything else becomes `%XX` over the UTF-8 bytes (mirrors
      # Node's `encodeURIComponent` / Go's `url.PathEscape`).
      def encode_segment(value)
        value.to_s.b.gsub(/[^A-Za-z0-9\-_.~]/n) { |byte| format("%%%02X", byte.ord) }
      end
    end
  end
end
