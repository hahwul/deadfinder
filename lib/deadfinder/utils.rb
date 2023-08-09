# frozen_string_literal: true

require 'uri'

def generate_url(text, base_url)
  node = text.to_s
  begin
    unless node.start_with?('http://', 'https://')
      uri = URI(base_url)
      if node.start_with? '//'
        return "#{uri.scheme}:#{node}"
      elsif node.start_with? '/'
        return "#{uri.scheme}://#{uri.host}#{node}"
      elsif ignore_scheme? node
        return nil
      else
        return "#{uri}#{node}"
      end
    end
  rescue StandardError
    # puts e
  end
  node
end

def ignore_scheme?(url)
  url.start_with?('mailto:', 'tel:', 'sms:', 'data:', 'file:')
end
