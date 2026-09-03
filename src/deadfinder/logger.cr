require "colorize"

module Deadfinder
  module Logger
    @@silent = false
    @@verbose = false
    @@debug = false
    # Where log lines go. Normally STDOUT, but `-o -` streams the report itself
    # on STDOUT, so the logs have to move aside or they interleave with (and
    # corrupt) the JSON/YAML/… a consumer is piping into `jq`.
    @@sink : IO = STDOUT
    @@mutex = Mutex.new

    # Per-target output buffers. Each target prints a coherent block
    # ("► Fetching …" → discovered → findings → "Task completed"), and
    # scanning several targets at once would interleave those blocks line by
    # line into an unreadable mess. So a target fiber can claim a buffer: every
    # line it — or a worker fiber it spawned — logs is collected there and
    # written to `@@sink` as one atomic block when the target finishes. Keyed by
    # fiber because logging happens deep inside call chains that have no idea
    # which target they belong to. No buffer is attached while only one target is
    # in flight, so single-target output still streams line by line, byte for
    # byte as before.
    @@buffers = {} of Fiber => IO::Memory

    def self.apply_options(options : Options)
      set_silent if options.silent
      set_verbose if options.verbose
      set_debug if options.debug
      self.sink = STDERR if options.output == Deadfinder::STDOUT_FILENAME
    end

    def self.sink : IO
      @@mutex.synchronize { @@sink }
    end

    def self.sink=(io : IO)
      @@mutex.synchronize { @@sink = io }
    end

    def self.reset_sink
      self.sink = STDOUT
    end

    def self.set_silent
      @@mutex.synchronize { @@silent = true }
    end

    def self.unset_silent
      @@mutex.synchronize { @@silent = false }
    end

    def self.silent?
      @@mutex.synchronize { @@silent }
    end

    def self.set_verbose
      @@mutex.synchronize { @@verbose = true }
    end

    def self.unset_verbose
      @@mutex.synchronize { @@verbose = false }
    end

    def self.verbose?
      @@mutex.synchronize { @@verbose }
    end

    def self.set_debug
      @@mutex.synchronize { @@debug = true }
    end

    def self.unset_debug
      @@mutex.synchronize { @@debug = false }
    end

    def self.debug?
      @@mutex.synchronize { @@debug }
    end

    def self.log(prefix : String, text : String, color : Symbol)
      return if silent?
      line = String.build do |io|
        case color
        when :yellow
          io << prefix.colorize(:yellow)
        when :blue
          io << prefix.colorize(:blue)
        when :red
          io << prefix.colorize(:red)
        when :green
          io << prefix.colorize(:green)
        else
          io << prefix
        end
        io << text
        io << '\n'
      end
      print_line(line)
    end

    def self.sub_log(prefix : String, is_end : Bool, text : String, color : Symbol)
      return if silent?
      indent = is_end ? "  \u2514\u2500\u2500 " : "  \u251C\u2500\u2500 "
      line = String.build do |io|
        case color
        when :yellow
          io << indent.colorize(:yellow)
          io << prefix.colorize(:yellow)
        when :blue
          io << indent.colorize(:blue)
          io << prefix.colorize(:blue)
        when :red
          io << indent.colorize(:red)
          io << prefix.colorize(:red)
        when :green
          io << indent.colorize(:green)
          io << prefix.colorize(:green)
        else
          io << indent
          io << prefix
        end
        io << text
        io << '\n'
      end
      print_line(line)
    end

    # Centralized writer. A closed/broken output stream (e.g. STDOUT piped to a
    # process that exited, like `... | head`) raises IO::Error; swallow it so
    # logging can never crash a scan or leave the worker accounting unbalanced.
    # `@@sink` is read directly rather than through `sink` because the mutex is
    # already held here and Crystal's Mutex is not reentrant.
    private def self.print_line(line : String)
      @@mutex.synchronize do
        # The `empty?` check keeps the common single-target path from hashing a
        # Fiber for every link checked.
        if !@@buffers.empty? && (buffer = @@buffers[Fiber.current]?)
          buffer << line
        else
          begin
            @@sink.print line
          rescue IO::Error
          end
        end
      end
    end

    # Collects everything the block logs (from this fiber and any fiber that
    # inherits the buffer via `with_buffer`) and writes it out as one block on
    # the way out, so concurrently scanned targets never shred each other's
    # output.
    def self.buffered(&)
      buffer = IO::Memory.new
      bind_buffer(buffer)
      begin
        yield
      ensure
        unbind_buffer
        flush_buffer(buffer)
      end
    end

    # The buffer the current fiber writes into, if any. Work fibers spawned on
    # a target's behalf must be handed this explicitly: they are separate keys
    # in the registry and would otherwise write straight to the sink, landing in
    # the middle of some other target's block.
    def self.current_buffer : IO::Memory?
      @@mutex.synchronize { @@buffers[Fiber.current]? }
    end

    # Routes everything the block logs into `buffer`. A nil buffer means the
    # parent was not buffering (single-target run), so this is a pass-through.
    def self.with_buffer(buffer : IO::Memory?, &)
      return yield if buffer.nil?
      bind_buffer(buffer)
      begin
        yield
      ensure
        unbind_buffer
      end
    end

    private def self.bind_buffer(buffer : IO::Memory) : Nil
      @@mutex.synchronize { @@buffers[Fiber.current] = buffer }
    end

    private def self.unbind_buffer : Nil
      @@mutex.synchronize { @@buffers.delete(Fiber.current) }
    end

    private def self.flush_buffer(buffer : IO::Memory) : Nil
      block = buffer.to_s
      return if block.empty?
      @@mutex.synchronize do
        begin
          @@sink.print block
        rescue IO::Error
        end
      end
    end

    def self.debug(text : String)
      log("\u2740 ", text, :yellow) if debug?
    end

    def self.info(text : String)
      log("\u2139 ", text, :blue)
    end

    def self.error(text : String)
      log("\u26A0\uFE0E ", text, :red)
    end

    def self.target(text : String)
      log("\u25BA ", text, :green)
    end

    def self.sub_info(text : String)
      log("  \u25CF ", text, :blue)
    end

    def self.sub_complete(text : String)
      sub_log("\u25CF ", true, text, :blue)
    end

    def self.found(text : String)
      sub_log("\u2718 ", false, text, :red)
    end

    def self.verbose(text : String)
      sub_log("\u279C ", false, text, :yellow) if verbose?
    end

    def self.verbose_ok(text : String)
      sub_log("\u2713 ", false, text, :green) if verbose?
    end
  end
end
