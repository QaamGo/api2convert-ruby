# frozen_string_literal: true

module Api2Convert
  module Resource
    # API usage statistics. The response shape is free-form (returned as-is).
    #
    # +filter+ is either an API key to scope to, or `"all"`.
    class Stats
      def initialize(transport)
        @transport = transport
      end

      # +day+ format `yyyy-mm-dd`.
      def day(day, filter = "all")
        @transport.request("GET", "/stats/day/#{seg(day)}/#{seg(filter)}")
      end

      # +month+ format `yyyy-mm`.
      def month(month, filter = "all")
        @transport.request("GET", "/stats/month/#{seg(month)}/#{seg(filter)}")
      end

      # +year+ format `yyyy`.
      def year(year, filter = "all")
        @transport.request("GET", "/stats/year/#{seg(year)}/#{seg(filter)}")
      end

      private

      def seg(value)
        Support::Data.encode_segment(value)
      end
    end
  end
end
