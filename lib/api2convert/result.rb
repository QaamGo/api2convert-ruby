# frozen_string_literal: true

require "fileutils"
require "tempfile"

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
      # API filename is used). The body is streamed chunk-by-chunk to a sibling temp
      # file (never buffered whole in memory), then atomically renamed over the
      # target only after a clean write+close — so an arbitrarily large output cannot
      # exhaust memory and a mid-stream failure never truncates the target nor
      # destroys a pre-existing complete file at that path. Returns the path written.
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
        # one must not (the X-Api2convert-Download-Password header could leak on a redirect).
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
        parent = File.dirname(target)
        parent = "." if parent.empty?
        # Stream to a sibling temp file and rename over the target only after a clean
        # write+close. This never truncates the target up front and never destroys a
        # pre-existing complete file on a mid-stream failure — a download either fully
        # replaces the target or leaves it untouched.
        temp = create_temp(parent, target)

        committed = false
        begin
          @transport.download(
            @output.uri, headers(password), follow_redirects: password.nil?, sink: temp
          )
          # Flush + close BEFORE the rename so a truncated-on-close write can never be
          # committed as a complete file, and a close/flush fault surfaces here rather
          # than being swallowed on the success path.
          temp.close
          File.rename(temp.path, target)
          committed = true
        rescue SystemCallError => e
          # A network read failure mid-stream is already a (non-retryable) NetworkError
          # raised by the sender, which is NOT a SystemCallError and so passes straight
          # through; reaching this rescue means a write / flush / rename fault — a
          # genuine filesystem error.
          raise Api2Convert::Error, "Could not write file: #{target}: #{e.message}"
        ensure
          # On any failure (network break, refused-redirect NetworkError, write/close/
          # rename fault) only the temp file is removed; the target is never touched
          # unless the rename already committed a complete download.
          unless committed
            begin
              temp.close unless temp.closed?
            rescue SystemCallError
              nil
            end
            FileUtils.rm_f(temp.path)
          end
        end
      end

      def create_temp(parent, target)
        temp = Tempfile.create([".a2c-download-", ".part"], parent)
        temp.binmode
        temp
      rescue SystemCallError
        raise Api2Convert::Error, "Could not open file for writing: #{target}"
      end

      def resolve_password(download_password)
        download_password.nil? ? @download_password : download_password
      end

      def headers(password)
        password.nil? ? {} : { "X-Api2convert-Download-Password" => password }
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
