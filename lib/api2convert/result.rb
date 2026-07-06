# frozen_string_literal: true

require "fileutils"

module Api2Convert
  module Result
    # A downloadable output file.
    #
    # Returned by `client.download(output)` and used internally by
    # {ConversionResult}. A password supplied at conversion time (or to
    # `client.download(output, password)`) is remembered and sent automatically on
    # every download; an explicit password argument to {#save}/{#contents}
    # overrides the remembered one for that call.
    class FileDownload
      def initialize(transport, output, download_password = nil)
        @transport = transport
        @output = output
        @download_password = download_password
      end

      # The self-contained download URL (no auth required).
      def url
        @output.uri
      end

      # Stream the file to disk. +path_or_dir+ is a file path, or a directory (the
      # API filename is used). The body is streamed straight to the file
      # chunk-by-chunk (never buffered whole in memory), so an arbitrarily large
      # output cannot exhaust memory. A mid-stream failure removes the partial file
      # so a truncated download never masquerades as a complete result. Returns the
      # path written to.
      def save(path_or_dir, download_password = nil)
        target = resolve_target(path_or_dir.to_s)
        parent = File.dirname(target)
        parent = "." if parent.empty?
        begin
          FileUtils.mkdir_p(parent)
        rescue SystemCallError
          raise Api2Convert::Error, "Could not create directory: #{parent}"
        end

        stream_to_file(target, resolve_password(download_password))
        target
      end

      # Download the file and return its contents. This buffers the whole body in
      # memory by design — use {#save} for a large file to stream it to disk.
      def contents(download_password = nil)
        password = resolve_password(download_password)
        # A passwordless download follows storage redirects; a password-protected
        # one must not (the X-Oc-Download-Password header could leak on a redirect).
        @transport.download(@output.uri, headers(password), follow_redirects: password.nil?)
      end

      # Redacted representation — the remembered download password is masked.
      def inspect
        "#<#{self.class.name} url=#{@output.uri.inspect} " \
          "download_password=#{Support::Secret.mask(@download_password)}>"
      end

      def to_s
        inspect
      end

      private

      def stream_to_file(target, password)
        success = false
        begin
          File.open(target, "wb") do |file|
            @transport.download(
              @output.uri, headers(password), follow_redirects: password.nil?, sink: file
            )
            success = true
          end
        rescue SystemCallError
          raise Api2Convert::Error, "Could not open file for writing: #{target}"
        ensure
          # Any failure (open error, network break, a refused-redirect NetworkError,
          # a mid-stream break) leaves a partial or empty file — remove it so a
          # truncated download can never masquerade as a complete result.
          FileUtils.rm_f(target) unless success
        end
      end

      def resolve_password(download_password)
        download_password.nil? ? @download_password : download_password
      end

      def headers(password)
        password.nil? ? {} : { "X-Oc-Download-Password" => password }
      end

      def resolve_target(path_or_dir)
        looks_like_dir = File.directory?(path_or_dir) ||
                         path_or_dir.end_with?("/") ||
                         path_or_dir.end_with?(File::SEPARATOR)
        if looks_like_dir
          name = safe_name(@output.filename) || safe_name(@output.id) || "output"
          return File.join(path_or_dir.sub(%r{[/\\]+\z}, ""), name)
        end
        path_or_dir
      end

      # Reduce an API-supplied name to a bare filename safe to append to a dir.
      # `output.filename` / `output.id` come straight from the API JSON, so a value
      # like `../../etc/cron.d/evil` (or one with separators or a NUL byte) must
      # never escape the caller's chosen directory. Returns nil when nothing usable
      # remains, so the caller can fall back.
      def safe_name(name)
        return nil if name.nil?

        base = File.basename(name.delete("\x00").tr("\\", "/")).strip
        # Reject a name that reduces to nothing usable. Note Ruby's File.basename("/")
        # is "/" (unlike POSIX basename -> ""), so a pure-separator name must be
        # caught here too, matching the sibling SDKs' fallback behavior.
        return nil if base == "." || base == ".." || base.delete("/").empty?

        base
      end
    end

    # The result of a completed conversion.
    #
    # The common case is one output: `result.save("out.pdf")`. Jobs that produce
    # several files expose them via {#outputs} and {#download}.
    class ConversionResult
      # @return [Model::Job] the completed job.
      attr_reader :job

      def initialize(job, transport, index = 0, download_password = nil)
        @job = job
        @transport = transport
        @index = index
        @download_password = download_password
      end

      # The selected output file (the first one by default).
      def output
        # Any index not present — including a negative one — raises rather than
        # wrapping around.
        if @index.negative? || @index >= @job.output.length
          raise Api2Convert::Error, "The job produced no output files."
        end

        @job.output[@index]
      end

      # All output files produced by the job.
      def outputs
        @job.output
      end

      # The download URL of the selected output (self-contained, no auth).
      def url
        output.uri
      end

      # Download the selected output to disk. Returns the path written to.
      def save(path_or_dir, download_password = nil)
        download.save(path_or_dir, download_password)
      end

      # Download the selected output and return its contents.
      def contents(download_password = nil)
        download.contents(download_password)
      end

      # A {FileDownload} for a specific output (defaults to the selected one).
      def download(output_file = nil)
        FileDownload.new(@transport, output_file.nil? ? output : output_file, @download_password)
      end

      # Redacted representation — the remembered download password is masked.
      def inspect
        "#<#{self.class.name} job=#{@job.id.inspect} outputs=#{@job.output.length} " \
          "download_password=#{Support::Secret.mask(@download_password)}>"
      end

      def to_s
        inspect
      end
    end
  end
end
