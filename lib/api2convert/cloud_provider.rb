# frozen_string_literal: true

module Api2Convert
  # The cloud storage providers the API can import inputs from and deliver
  # outputs to — the values of a cloud descriptor's `source` (input) / `type`
  # (output) field.
  #
  # This is **build-side vocabulary only**: it types the input builder
  # ({Model::CloudInput}) and output-target serialization ({Model::OutputTarget}).
  # Read models keep `source`/`type`/`status` as raw strings, so an unknown
  # provider string returned by the server round-trips untyped and never raises —
  # there is deliberately no strict parse.
  #
  # Import support (a {Model::CloudInput} factory) exists for {AMAZON_S3},
  # {AZURE}, {FTP} and {GOOGLE_CLOUD}. {GDRIVE} and {YOUTUBE} are **output-only**
  # (they validate as an output `type` but have no downloader); Google Drive
  # *input* uses the separate `gdrive_picker` input type.
  module CloudProvider
    AMAZON_S3 = "amazons3"
    AZURE = "azure"
    FTP = "ftp"
    GDRIVE = "gdrive"
    GOOGLE_CLOUD = "googlecloud"
    YOUTUBE = "youtube"

    # The full provider vocabulary, in canonical order.
    ALL = [AMAZON_S3, AZURE, FTP, GDRIVE, GOOGLE_CLOUD, YOUTUBE].freeze
  end
end
