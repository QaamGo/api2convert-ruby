# frozen_string_literal: true

module Api2Convert
  module Webhook
    # A verified webhook callback. The API posts the job whose status changed.
    class Event
      # @return [Model::Job] the job whose status changed.
      attr_reader :job
      # @return [Hash] the full decoded callback body.
      attr_reader :payload

      def initialize(job, payload)
        @job = job
        @payload = payload
        freeze
      end

      def self.from_hash(payload)
        new(Model::Job.from_hash(payload), payload)
      end
    end
  end
end
