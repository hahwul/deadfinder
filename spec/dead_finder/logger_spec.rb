# frozen_string_literal: true

require_relative '../../lib/deadfinder/logger'
require 'stringio'

RSpec.describe Logger do
  let(:original_stdout) { $stdout }

  after do
    $stdout = original_stdout
  end

  describe '.silent?' do
    it 'returns false by default' do
      expect(described_class.silent?).to be false
    end
  end

  describe '.set_silent' do
    it 'sets the silent mode to true' do
      described_class.set_silent
      expect(described_class.silent?).to be true
    end
  end

  describe '.unset_silent' do
    it 'sets the silent mode to false' do
      described_class.set_silent
      described_class.unset_silent
      expect(described_class.silent?).to be false
    end
  end

  describe '.info' do
    it 'prints info message when not in silent mode' do
      expect { described_class.info('Test info') }.to output("\e[0;34;49mℹ \e[0mTest info\n").to_stdout
    end

    it 'does not print info message when in silent mode' do
      described_class.set_silent
      expect { described_class.info('Test info') }.not_to output.to_stdout
    end
  end

  describe '.error' do
    it 'prints error message when not in silent mode' do
      described_class.unset_silent
      expect { described_class.error('Test error') }.to output("\e[0;31;49m⚠︎ \e[0mTest error\n").to_stdout
    end

    it 'does not print error message when in silent mode' do
      described_class.set_silent
      expect { described_class.error('Test error') }.not_to output.to_stdout
    end
  end

  describe '.target' do
    it 'prints target message when not in silent mode' do
      described_class.unset_silent
      expect { described_class.target('Test target') }.to output("\e[0;32;49m► \e[0mTest target\n").to_stdout
    end

    it 'does not print target message when in silent mode' do
      described_class.set_silent
      expect { described_class.target('Test target') }.not_to output.to_stdout
    end
  end

  describe '.sub_info' do
    it 'prints sub_info message when not in silent mode' do
      described_class.unset_silent
      expect { described_class.sub_info('Test sub_info') }.to output("\e[0;34;49m  ● \e[0mTest sub_info\n").to_stdout
    end

    it 'does not print sub_info message when in silent mode' do
      described_class.set_silent
      expect { described_class.sub_info('Test sub_info') }.not_to output.to_stdout
    end
  end

  describe '.sub_complete' do
    it 'prints sub_complete message when not in silent mode' do
      described_class.unset_silent
      expect { described_class.sub_complete('Test sub_complete') }.to output("\e[0;34;49m  └── \e[0m\e[0;34;49m● \e[0mTest sub_complete\n").to_stdout
    end

    it 'does not print sub_complete message when in silent mode' do
      described_class.set_silent
      expect { described_class.sub_complete('Test sub_complete') }.not_to output.to_stdout
    end
  end
end
