module Deadfinder
  IGNORED_SCHEMES = ["mailto:", "tel:", "sms:", "data:", "file:", "javascript:", "#"]

  # Byte-order mark that Windows/Excel-exported URL lists carry on their first
  # line. It is not whitespace, so `String#strip` leaves it attached to the URL
  # and quietly corrupts the very first target.
  UTF8_BOM = "\uFEFF"

  def self.ignore_scheme?(url : String) : Bool
    IGNORED_SCHEMES.any? { |scheme| url.starts_with?(scheme) }
  end

  # True when `target` can actually be scanned: an absolute URL with an
  # http/https scheme and a non-empty host. Everything else only produces a
  # confusing failure downstream — a bare domain and a stray shell token both
  # raise "URI is missing a host", `file:///etc/hosts` parses to an empty host
  # and tries to connect to `:80`, and `ftp://host/x` would be fetched as plain
  # HTTP — so callers report such lines and skip them instead.
  def self.valid_target?(target : String) : Bool
    uri = URI.parse(target)
    scheme = uri.scheme
    return false unless scheme == "http" || scheme == "https"
    !uri.host.presence.nil?
  rescue
    false
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

    # URL schemes are case-insensitive (RFC 3986 §3.1), so `HTTP://` / `HTTPS://`
    # are absolute URLs too. Normalize only the scheme to lowercase — the rest of
    # the URL is left verbatim — so downstream SSL detection (`scheme == "https"`)
    # works and the link isn't silently dropped by the resolver below.
    if node.size >= 7 && node[0, 7].compare("http://", case_insensitive: true) == 0
      return "http://" + node[7..]
    elsif node.size >= 8 && node[0, 8].compare("https://", case_insensitive: true) == 0
      return "https://" + node[8..]
    end

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
