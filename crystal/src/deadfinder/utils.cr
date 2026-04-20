module Deadfinder
  IGNORED_SCHEMES = ["mailto:", "tel:", "sms:", "data:", "file:", "javascript:", "#"]

  def self.ignore_scheme?(url : String) : Bool
    IGNORED_SCHEMES.any? { |scheme| url.starts_with?(scheme) }
  end

  def self.generate_url(text : String, base_url : String) : String?
    node = text.strip
    return nil if node.empty?
    return node if node.starts_with?("http://") || node.starts_with?("https://")

    begin
      uri = URI.parse(base_url)
      return nil unless uri.scheme && uri.host
      if node.starts_with?("//")
        "#{uri.scheme}:#{node}"
      elsif node.starts_with?("/")
        "#{origin(uri)}#{node}"
      elsif ignore_scheme?(node)
        nil
      else
        # Resolve relative URL against base
        resolve_relative_url(node, base_url)
      end
    rescue
      nil
    end
  end

  private def self.origin(uri : URI) : String
    if port = uri.port
      "#{uri.scheme}://#{uri.host}:#{port}"
    else
      "#{uri.scheme}://#{uri.host}"
    end
  end

  private def self.resolve_relative_url(relative : String, base : String) : String?
    begin
      base_uri = URI.parse(base)
      return nil unless base_uri.scheme && base_uri.host
      base_path = base_uri.path
      # If base path ends with /, append relative directly
      # Otherwise, replace last segment
      if base_path.ends_with?("/")
        resolved_path = base_path + relative
      else
        last_slash = base_path.rindex('/')
        if last_slash
          resolved_path = base_path[0..last_slash] + relative
        else
          resolved_path = "/" + relative
        end
      end
      "#{origin(base_uri)}#{resolved_path}"
    rescue
      nil
    end
  end
end
