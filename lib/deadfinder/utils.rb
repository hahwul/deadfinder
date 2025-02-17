# frozen_string_literal: true

require 'uri'

def generate_url(text, base_url)
  node = text.to_s
  return node if node.start_with?('http://', 'https://')

  begin
    uri = URI(base_url)
    if node.start_with?('//')
      "#{uri.scheme}:#{node}"
    elsif node.start_with?('/')
      "#{uri.scheme}://#{uri.host}#{node}"
    elsif ignore_scheme?(node)
      nil
    else
      URI.join(base_url, node).to_s
    end
  rescue StandardError
    nil
  end
end

def ignore_scheme?(url)
  url.start_with?('mailto:', 'tel:', 'sms:', 'data:', 'file:')
end
