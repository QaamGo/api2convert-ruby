# frozen_string_literal: true

module Api2Convert
  module Model
    # A cloud-storage delivery target for a conversion's output:
    # `{ type:<provider>, parameters, credentials }`.
    #
    # Attach one (or more) to a conversion via
    # `client.convert(..., output_targets: [...])` / `convert_async(...)`, or
    # inline in a raw `jobs.create` conversion map. When any output target is set
    # the conversion delivers straight to your storage and produces **no** local
    # output — so `convert` returns the completed job without downloading.
    #
    # This wave ships the **generic** shape only (`type` + free-form
    # `parameters`/`credentials`); the per-provider output keys live in a separate
    # service and diverge per provider, so there are no per-provider output
    # factories yet.
    #
    # Serialization ({#to_h}) emits `{ type, parameters, credentials }` and
    # **omits `status`** (server-set, read-only). On read ({.from_hash}) `type`,
    # `parameters` and `status` round-trip as raw values; `credentials` are
    # **never** surfaced (the API returns them empty). `credentials` ride in the
    # plaintext body, so {#inspect} masks the whole object to `[REDACTED]`.
    class OutputTarget
      attr_reader :type, :parameters, :credentials, :status

      # +status+ is server-set on read (`waiting|uploading|completed|failed`) and
      # never sent on create.
      def initialize(type:, parameters: {}, credentials: {}, status: nil)
        @type = type
        @parameters = parameters
        @credentials = credentials
        @status = status
        freeze
      end

      # Generic constructor accepting a {CloudProvider} constant or a
      # forward-compat string.
      def self.of(type, parameters: {}, credentials: {})
        new(type: type.to_s, parameters: parameters, credentials: credentials)
      end

      # The wire descriptor sent on create — `{ type, parameters, credentials }`,
      # with `status` omitted (server-set, read-only).
      def to_h
        {
          "type" => @type,
          "parameters" => @parameters,
          "credentials" => @credentials
        }
      end

      # Hydrate from a `GET /jobs/{id}` `output_target[]` element. `type`/`status`
      # stay raw strings (an unknown provider round-trips untyped); `credentials`
      # are deliberately not surfaced.
      def self.from_hash(data)
        d = Support::Data.as_object(data)
        new(
          type: Support::Data.as_str(d["type"]),
          parameters: Support::Data.as_object(d["parameters"]),
          credentials: {},
          status: Support::Data.nullable_str(d["status"])
        )
      end

      # Redacted representation — credentials masked. Safe to log.
      def inspect
        "#<#{self.class.name} type=#{@type.inspect} " \
          "parameters=#{Support::Redactor.parameters(@parameters).inspect} " \
          "credentials=#{Support::Redactor::MARKER} status=#{@status.inspect}>"
      end

      def to_s
        inspect
      end
    end
  end
end
