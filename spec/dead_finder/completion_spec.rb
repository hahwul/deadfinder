# frozen_string_literal: true

require 'deadfinder/completion'

RSpec.describe DeadFinder::Completion do
  describe '.bash' do
    it 'returns the bash completion script' do
      script = described_class.bash
      expect(script).to include('_deadfinder_completions')
      expect(script).to include('complete -F _deadfinder_completions deadfinder')
    end
  end

  describe '.zsh' do
    it 'returns the zsh completion script' do
      script = described_class.zsh
      expect(script).to include('#compdef deadfinder')
      expect(script).to include('_arguments \\')
    end
  end

  describe '.fish' do
    it 'returns the fish completion script' do
      script = described_class.fish
      expect(script).to include('complete -c deadfinder -l include30x')
      expect(script).to include('complete -c deadfinder -l debug -d \'Debug mode\'')
    end
  end
end
