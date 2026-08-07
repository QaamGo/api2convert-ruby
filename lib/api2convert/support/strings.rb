# frozen_string_literal: true

module Api2Convert
  module Support
    # Small string helpers shared across the SDK. Internal, not part of the public API.
    module Strings
      module_function

      # Strip every trailing character contained in +chars+ from +value+.
      #
      # Deliberately a scan rather than a regex: %r{/+\z} and friends backtrack, so a
      # string ending in a long run of separators costs O(n^2) to match (CodeQL's
      # +rb/polynomial-redos+). +job.server+ arrives from the API and +base_url+ from
      # caller config, so neither is worth a quadratic path. This is a single reverse
      # scan — O(n), no backtracking, identical result.
      def trim_trailing(value, chars)
        last = value.length
        last -= 1 while last.positive? && chars.include?(value[last - 1])
        last == value.length ? value : value[0, last]
      end
    end
  end
end
