# frozen_string_literal: true

module Api2Convert
  # Well-known job status codes (the `status.code` field).
  #
  # The API may introduce further codes; treat any code not listed here as
  # non-terminal. Use {terminal?} for a raw status string rather than comparing
  # by hand.
  module JobStatus
    CREATED = "created"
    INCOMPLETE = "incomplete"
    DOWNLOADING = "downloading"
    QUEUED = "queued"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELED = "canceled"

    # The finished states — a job in one of these will not change further.
    TERMINAL = [COMPLETED, FAILED, CANCELED].freeze

    module_function

    # Is the given raw status code terminal? Unknown codes are non-terminal.
    def terminal?(code)
      TERMINAL.include?(code)
    end
  end
end
