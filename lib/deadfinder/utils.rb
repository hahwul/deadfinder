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
      elsif node.start_with? 'mailto:'
        return nil
      else
        return "#{uri}#{node}"
      end
    end
  rescue StandardError => e
    # puts e
  end
  node
end
