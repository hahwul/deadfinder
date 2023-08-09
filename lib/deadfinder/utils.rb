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
        return "#{extract_directory(uri)}#{node}"
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

def extract_directory(uri)
  if uri.path.end_with?('/')
    return "#{uri.scheme}://#{uri.host}#{uri.path}"
  end

  path_components = uri.path.split('/')
  last_component = path_components.last
  path_components.pop

  directory_path = path_components.join('/')

  if directory_path.start_with?('/')
    "#{uri.scheme}://#{uri.host}#{directory_path}/"
  else
    "#{uri.scheme}://#{uri.host}/#{directory_path}/"
  end
end
