module Deadfinder
  IGNORED_SCHEMES = ["mailto:", "tel:", "sms:", "data:", "file:", "javascript:", "#"]

  def self.ignore_scheme?(url : String) : Bool
    IGNORED_SCHEMES.any? { |scheme| url.starts_with?(scheme) }
  end

  def self.generate_url(text : String, base_url : String) : String?
    # Browsers strip ASCII tab/newline/CR from inside a URL before navigating,
    # so `java\tscript:alert(1)` is a javascript: link to them. Mirror that here
    # so such obfuscated pseudo-schemes are caught by ignore_scheme? below
    # instead of being resolved into a bogus request target.
    node = text.delete("\t\n\r").strip
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
