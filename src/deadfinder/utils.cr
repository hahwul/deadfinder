module Deadfinder
  IGNORED_SCHEMES = ["mailto:", "tel:", "sms:", "data:", "file:", "javascript:", "#"]

  def self.ignore_scheme?(url : String) : Bool
    IGNORED_SCHEMES.any? { |scheme| url.starts_with?(scheme) }
  end

  def self.generate_url(text : String, base_url : String) : String?
    node = text.strip
    return nil if node.empty?
    return node if node.starts_with?("http://") || node.starts_with?("https://")
    return nil if ignore_scheme?(node)

    begin
      base_uri = URI.parse(base_url)
      return nil unless base_uri.scheme && base_uri.host

      resolved = base_uri.resolve(node)
      if resolved.scheme == "http" || resolved.scheme == "https"
        resolved.to_s
      else
        nil
      end
    rescue
      nil
    end
  end
end
