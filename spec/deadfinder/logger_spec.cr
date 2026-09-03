require "../spec_helper"

describe Deadfinder::Logger do
  before_each do
    Deadfinder::Logger.unset_silent
    Deadfinder::Logger.unset_verbose
    Deadfinder::Logger.unset_debug
  end

  describe ".apply_options" do
    it "sets silent mode when options has silent" do
      options = Deadfinder::Options.new
      options.silent = true
      options.verbose = false
      options.debug = false
      Deadfinder::Logger.apply_options(options)
      Deadfinder::Logger.silent?.should be_true
    end

    it "sets verbose mode when options has verbose" do
      options = Deadfinder::Options.new
      options.silent = false
      options.verbose = true
      options.debug = false
      Deadfinder::Logger.apply_options(options)
      Deadfinder::Logger.verbose?.should be_true
    end

    it "sets debug mode when options has debug" do
      options = Deadfinder::Options.new
      options.silent = false
      options.verbose = false
      options.debug = true
      Deadfinder::Logger.apply_options(options)
      Deadfinder::Logger.debug?.should be_true
    end

    it "sets multiple modes simultaneously" do
      options = Deadfinder::Options.new
      options.silent = true
      options.verbose = true
      options.debug = true
      Deadfinder::Logger.apply_options(options)
      Deadfinder::Logger.silent?.should be_true
      Deadfinder::Logger.verbose?.should be_true
      Deadfinder::Logger.debug?.should be_true
    end
  end

  describe ".silent?" do
    it "returns false by default" do
      Deadfinder::Logger.silent?.should be_false
    end
  end

  describe ".set_silent / .unset_silent" do
    it "sets and unsets silent mode" do
      Deadfinder::Logger.set_silent
      Deadfinder::Logger.silent?.should be_true
      Deadfinder::Logger.unset_silent
      Deadfinder::Logger.silent?.should be_false
    end
  end

  describe ".verbose?" do
    it "returns false by default" do
      Deadfinder::Logger.verbose?.should be_false
    end
  end

  describe ".set_verbose / .unset_verbose" do
    it "sets and unsets verbose mode" do
      Deadfinder::Logger.set_verbose
      Deadfinder::Logger.verbose?.should be_true
      Deadfinder::Logger.unset_verbose
      Deadfinder::Logger.verbose?.should be_false
    end
  end

  describe ".debug?" do
    it "returns false by default" do
      Deadfinder::Logger.debug?.should be_false
    end
  end

  describe ".set_debug / .unset_debug" do
    it "sets and unsets debug mode" do
      Deadfinder::Logger.set_debug
      Deadfinder::Logger.debug?.should be_true
      Deadfinder::Logger.unset_debug
      Deadfinder::Logger.debug?.should be_false
    end
  end

  describe "target output buffering" do
    it "collects a fiber's lines in its sink instead of writing them out" do
      sink = IO::Memory.new
      Deadfinder::Logger.with_buffer(sink) do
        Deadfinder::Logger.target "Fetching http://buffered.test"
        Deadfinder::Logger.sub_info "Discovered 1 URLs, currently checking them. [anchor:1]"
        Deadfinder::Logger.found "[404] http://buffered.test/gone"
        Deadfinder::Logger.sub_complete "Task completed"
      end

      text = sink.to_s
      text.should contain "Fetching http://buffered.test"
      text.should contain "Discovered 1 URLs"
      text.should contain "[404] http://buffered.test/gone"
      text.should contain "Task completed"
      text.lines.size.should eq 4
    end

    it "keeps concurrently logged blocks from interleaving" do
      sinks = [IO::Memory.new, IO::Memory.new]
      done = Channel(Nil).new

      sinks.each_with_index do |sink, i|
        spawn do
          Deadfinder::Logger.with_buffer(sink) do
            3.times do |n|
              Deadfinder::Logger.found "[404] http://t#{i}.test/#{n}"
              # Hand control to the other "target" mid-block: this is exactly
              # the point at which unbuffered output used to shred.
              Fiber.yield
            end
          end
          done.send(nil)
        end
      end
      2.times { done.receive }

      sinks.each_with_index do |sink, i|
        lines = sink.to_s.lines
        lines.size.should eq 3
        lines.all?(&.includes?("http://t#{i}.test/")).should be_true
      end
    end

    it "hands the sink to fibers spawned on the target's behalf" do
      sink = IO::Memory.new
      done = Channel(Nil).new

      Deadfinder::Logger.with_buffer(sink) do
        inherited = Deadfinder::Logger.current_buffer
        spawn do
          Deadfinder::Logger.with_buffer(inherited) do
            Deadfinder::Logger.found "[404] http://worker.test/gone"
          end
          done.send(nil)
        end
        done.receive
      end

      sink.to_s.should contain "http://worker.test/gone"
    end

    it "releases the sink again on the way out" do
      Deadfinder::Logger.current_buffer.should be_nil
      Deadfinder::Logger.with_buffer(IO::Memory.new) do
        Deadfinder::Logger.current_buffer.should_not be_nil
      end
      Deadfinder::Logger.current_buffer.should be_nil
    end

    it "passes straight through when no sink is bound" do
      # A nil sink is what keeps single-target runs streaming line by line
      # instead of arriving in one burst at the end.
      Deadfinder::Logger.with_buffer(nil) { Deadfinder::Logger.current_buffer }.should be_nil
    end

    it "buffers and then flushes without leaving the sink bound" do
      Deadfinder::Logger.set_silent
      Deadfinder::Logger.buffered do
        Deadfinder::Logger.current_buffer.should_not be_nil
        Deadfinder::Logger.target "Fetching http://flushed.test"
      end
      Deadfinder::Logger.current_buffer.should be_nil
    end
  end

  describe "output suppression in silent mode" do
    it "does not output when silent" do
      Deadfinder::Logger.set_silent
      # These should not raise and should produce no visible output
      Deadfinder::Logger.info("test")
      Deadfinder::Logger.error("test")
      Deadfinder::Logger.target("test")
      Deadfinder::Logger.sub_info("test")
      Deadfinder::Logger.sub_complete("test")
      Deadfinder::Logger.found("test")
    end
  end
end
