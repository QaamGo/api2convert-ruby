# frozen_string_literal: true

module Api2Convert
  # The kinds of source an input file can be created from (the input `type`
  # field). A typed reference for building input descriptors by hand, e.g.
  # `add_input(job_id, { "type" => Api2Convert::InputType::REMOTE, "source" => ... })`.
  module InputType
    UPLOAD = "upload"
    REMOTE = "remote"
    OUTPUT = "output"
    INPUT_ID = "input_id"
    GDRIVE_PICKER = "gdrive_picker"
    BASE64 = "base64"
    CLOUD = "cloud"
  end
end
