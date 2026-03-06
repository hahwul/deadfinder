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
