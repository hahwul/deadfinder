# frozen_string_literal: true

require 'uri'

# Generates a full URL from a potentially relative URL and a base URL
# @param text [String] The URL or path to convert
# @param base_url [String, URI] The base URL to resolve relative paths against
# @return [String, nil] The generated absolute URL, or nil if the URL should be ignored
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

# Checks if a URL scheme should be ignored
# @param url [String] The URL to check
# @return [Boolean] true if the URL scheme should be ignored
def ignore_scheme?(url)
  url.start_with?('mailto:', 'tel:', 'sms:', 'data:', 'file:')
end
