# frozen_string_literal: true

require 'webmock/rspec'

# ...existing code...

WebMock.disable_net_connect!(allow_localhost: true)

# ...existing code...
