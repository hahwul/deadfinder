# frozen_string_literal: true

require_relative '../../lib/deadfinder/logger'
require 'stringio'

RSpec.describe DeadFinder::Logger do
  let(:original_stdout) { $stdout }

  after do
    $stdout = original_stdout
  end

  describe '.apply_options' do
    it 'sets silent mode when options has silent' do
      expect(described_class).to receive(:set_silent)
      described_class.apply_options('silent' => true)
    end

    it 'sets verbose mode when options has verbose' do
      expect(described_class).to receive(:set_verbose)
      described_class.apply_options('verbose' => true)
    end

    it 'sets debug mode when options has debug' do
      expect(described_class).to receive(:set_debug)
      described_class.apply_options('debug' => true)
    end
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

  describe '.verbose?' do
    it 'returns false by default' do
      expect(described_class.verbose?).to be false
    end
  end

  describe '.set_verbose' do
    it 'sets the verbose mode to true' do
      described_class.set_verbose
      expect(described_class.verbose?).to be true
    end
  end

  describe '.unset_verbose' do
    it 'sets the verbose mode to false' do
      described_class.set_verbose
      described_class.unset_verbose
      expect(described_class.verbose?).to be false
    end
  end

  describe '.debug?' do
    it 'returns false by default' do
      expect(described_class.debug?).to be false
    end
  end

  describe '.set_debug' do
    it 'sets the debug mode to true' do
      described_class.set_debug
      expect(described_class.debug?).to be true
    end
  end

  describe '.unset_debug' do
    it 'sets the debug mode to false' do
      described_class.set_debug
      described_class.unset_debug
      expect(described_class.debug?).to be false
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

  describe '.found' do
    it 'prints found message when not in silent mode' do
      described_class.unset_silent
      expect { described_class.found('Test found') }.to output("\e[0;31;49m  ├── \e[0m\e[0;31;49m✘ \e[0mTest found\n").to_stdout
    end

    it 'does not print found message when in silent mode' do
      described_class.set_silent
      expect { described_class.found('Test found') }.not_to output.to_stdout
    end
  end

  describe '.verbose' do
    it 'prints verbose message when not in silent mode' do
      described_class.unset_silent
      described_class.set_verbose
      expect { described_class.verbose('Test verbose') }.to output("\e[0;33;49m  ├── \e[0m\e[0;33;49m➜ \e[0mTest verbose\n").to_stdout
    end

    it 'does not print verbose message when in silent mode' do
      described_class.set_silent
      expect { described_class.verbose('Test verbose') }.not_to output.to_stdout
    end
  end

  describe '.verbose_ok' do
    it 'prints verbose_ok message when not in silent mode' do
      described_class.unset_silent
      described_class.set_verbose
      expect { described_class.verbose_ok('Test verbose_ok') }.to output("\e[0;32;49m  ├── \e[0m\e[0;32;49m✓ \e[0mTest verbose_ok\n").to_stdout
    end

    it 'does not print verbose_ok message when in silent mode' do
      described_class.set_silent
      expect { described_class.verbose_ok('Test verbose_ok') }.not_to output.to_stdout
    end
  end
end
