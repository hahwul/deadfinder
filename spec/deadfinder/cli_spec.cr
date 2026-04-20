require "../spec_helper"

describe Deadfinder::CLI do
  before_each do
    WebMock.reset
    reset_deadfinder_state
  end

  describe "Options defaults" do
    it "has correct default values" do
      options = Deadfinder::Options.new
      options.concurrency.should eq 50
      options.timeout.should eq 10
      options.output.should eq ""
      options.output_format.should eq "json"
      options.headers.should eq [] of String
      options.worker_headers.should eq [] of String
      options.silent.should be_false
      options.verbose.should be_false
      options.debug.should be_false
      options.include30x.should be_false
      options.proxy.should eq ""
      options.proxy_auth.should eq ""
      options.match.should eq ""
      options.ignore.should eq ""
      options.coverage.should be_false
      options.visualize.should eq ""
      options.limit.should eq 0
    end
  end

  describe "completion scripts" do
    it "generates bash completion script" do
      script = Deadfinder::Completion.bash
      script.should contain "_deadfinder_completions"
      script.should contain "complete -F _deadfinder_completions deadfinder"
      script.should contain "COMPREPLY"
    end

    it "generates zsh completion script" do
      script = Deadfinder::Completion.zsh
      script.should contain "#compdef deadfinder"
      script.should contain "_arguments"
      script.should contain "--include30x"
    end

    it "generates fish completion script" do
      script = Deadfinder::Completion.fish
      script.should contain "complete -c deadfinder -l include30x"
      script.should contain "complete -c deadfinder -l debug -d 'Debug mode'"
      script.should contain "complete -c deadfinder -l concurrency"
    end
  end

  describe "version" do
    it "has correct version" do
      Deadfinder::VERSION.should eq "2.0.1"
    end
  end
end
