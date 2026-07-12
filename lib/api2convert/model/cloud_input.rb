# frozen_string_literal: true

module Api2Convert
  module Model
    # A cloud-storage input descriptor:
    # `{ type:"cloud", source:<provider>, parameters, credentials }`.
    #
    # Hand it to `client.convert` / `convert_async` as the input, or to
    # `client.jobs.add_input(job_id, cloud_input)`; either way it emits the wire
    # descriptor via {#to_h}. Like a remote URL, a cloud input is a **started**
    # job (`process => true`), not a staged upload.
    #
    # The per-provider factories carry each provider's required keys **verbatim**
    # — flat and lowercase, exactly as the API expects (`accesskeyid`, not
    # `access_key_id`). The required keys are constructor arguments (structural
    # correctness), **not** a runtime gate: the builder never rejects a descriptor
    # the permissive, asynchronously-validating server would accept. Optional and
    # forward-compat keys go through the trailing +parameters+ / +credentials+
    # maps, or the generic {.of} escape hatch.
    #
    # Google Drive *input* uses the `gdrive_picker` input type (the generic
    # `add_input` raw-map path this wave); `gdrive`/`youtube` are output-only.
    #
    # `credentials` ride in the plaintext body, so {#inspect} masks the **whole**
    # credentials object to `[REDACTED]` and any sensitive `parameters` leaf.
    class CloudInput
      attr_reader :source, :parameters, :credentials

      # +source+ is the provider string; +parameters+ are non-secret locator keys
      # (`bucket`, `file`, `host`, …); +credentials+ are secret keys.
      def initialize(source:, parameters: {}, credentials: {})
        @source = source
        @parameters = parameters
        @credentials = credentials
        freeze
      end

      # Generic escape hatch: any provider (a {CloudProvider} constant or a
      # forward-compat string) with free-form maps.
      def self.of(source, parameters: {}, credentials: {})
        new(source: source.to_s, parameters: parameters, credentials: credentials)
      end

      # Import from Amazon S3. Extra/forward-compat keys merge into
      # +parameters+ / +credentials+.
      def self.amazon_s3(bucket:, file:, accesskeyid:, secretaccesskey:,
                         parameters: {}, credentials: {})
        new(
          source: CloudProvider::AMAZON_S3,
          parameters: { "bucket" => bucket, "file" => file }.merge(parameters),
          credentials: { "accesskeyid" => accesskeyid, "secretaccesskey" => secretaccesskey }
            .merge(credentials)
        )
      end

      # Import from Azure Blob Storage.
      def self.azure(container:, file:, accountname:, accountkey:,
                     parameters: {}, credentials: {})
        new(
          source: CloudProvider::AZURE,
          parameters: { "container" => container, "file" => file }.merge(parameters),
          credentials: { "accountname" => accountname, "accountkey" => accountkey }.merge(credentials)
        )
      end

      # Import from an FTP server.
      def self.ftp(host:, file:, username:, password:, parameters: {}, credentials: {})
        new(
          source: CloudProvider::FTP,
          parameters: { "host" => host, "file" => file }.merge(parameters),
          credentials: { "username" => username, "password" => password }.merge(credentials)
        )
      end

      # Import from Google Cloud Storage.
      def self.google_cloud(projectid:, bucket:, file:, keyfile:, parameters: {}, credentials: {})
        new(
          source: CloudProvider::GOOGLE_CLOUD,
          parameters: { "projectid" => projectid, "bucket" => bucket, "file" => file }.merge(parameters),
          credentials: { "keyfile" => keyfile }.merge(credentials)
        )
      end

      # The wire descriptor sent to `POST /jobs` (inline `input`) or
      # `POST /jobs/{id}/input`.
      def to_h
        {
          "type" => InputType::CLOUD,
          "source" => @source,
          "parameters" => @parameters,
          "credentials" => @credentials
        }
      end

      # Redacted representation — the whole `credentials` object renders as
      # `[REDACTED]`; sensitive `parameters` leaves are masked too. Safe to log.
      def inspect
        "#<#{self.class.name} type=cloud source=#{@source.inspect} " \
          "parameters=#{Support::Redactor.parameters(@parameters).inspect} " \
          "credentials=#{Support::Redactor::MARKER}>"
      end

      def to_s
        inspect
      end
    end
  end
end
