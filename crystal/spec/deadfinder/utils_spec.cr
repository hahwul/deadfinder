require "../spec_helper"

describe "Deadfinder.generate_url" do
  base_url = "http://example.com/base/"

  it "returns the original URL if it starts with http://" do
    Deadfinder.generate_url("http://example.com", base_url).should eq "http://example.com"
  end

  it "returns the original URL if it starts with https://" do
    Deadfinder.generate_url("https://example.com", base_url).should eq "https://example.com"
  end

  it "prepends the scheme if the URL starts with //" do
    Deadfinder.generate_url("//example.com", base_url).should eq "http://example.com"
  end

  it "prepends the scheme and host if the URL starts with /" do
    Deadfinder.generate_url("/path", base_url).should eq "http://example.com/path"
  end

  it "returns nil if the URL should ignore the scheme" do
    Deadfinder.generate_url("mailto:test@example.com", base_url).should be_nil
  end

  it "prepends the base directory if the URL is relative" do
    Deadfinder.generate_url("relative/path", base_url).should eq "http://example.com/base/relative/path"
  end

  it "returns nil if base_url is invalid" do
    Deadfinder.generate_url("relative/path", "://invalid").should be_nil
  end

  it "returns nil for empty text" do
    Deadfinder.generate_url("", base_url).should be_nil
  end

  it "returns nil for whitespace-only text" do
    Deadfinder.generate_url("   ", base_url).should be_nil
  end

  it "returns nil for javascript: scheme" do
    Deadfinder.generate_url("javascript:void(0)", base_url).should be_nil
  end

  it "returns nil for data: scheme" do
    Deadfinder.generate_url("data:text/plain,hello", base_url).should be_nil
  end

  it "returns nil for fragment-only (#) links" do
    Deadfinder.generate_url("#section", base_url).should be_nil
  end

  it "handles protocol-relative URLs with https base" do
    Deadfinder.generate_url("//cdn.example.com/lib.js", "https://example.com/").should eq "https://cdn.example.com/lib.js"
  end

  it "resolves relative URL when base path does not end with /" do
    Deadfinder.generate_url("page.html", "http://example.com/dir/index.html").should eq "http://example.com/dir/page.html"
  end

  it "handles root-relative paths" do
    Deadfinder.generate_url("/about", "https://example.com/some/deep/path").should eq "https://example.com/about"
  end

  it "preserves non-default port when resolving root-relative paths" do
    Deadfinder.generate_url("/about", "http://127.0.0.1:8080/index.html").should eq "http://127.0.0.1:8080/about"
  end

  it "preserves non-default port when resolving relative paths" do
    Deadfinder.generate_url("about", "http://127.0.0.1:8080/index.html").should eq "http://127.0.0.1:8080/about"
  end

  it "preserves non-default port when base path is a directory" do
    Deadfinder.generate_url("page.html", "http://127.0.0.1:8080/dir/").should eq "http://127.0.0.1:8080/dir/page.html"
  end
end

describe "Deadfinder.ignore_scheme?" do
  it "returns true for mailto: URLs" do
    Deadfinder.ignore_scheme?("mailto:test@example.com").should be_true
  end

  it "returns true for tel: URLs" do
    Deadfinder.ignore_scheme?("tel:1234567890").should be_true
  end

  it "returns true for sms: URLs" do
    Deadfinder.ignore_scheme?("sms:1234567890").should be_true
  end

  it "returns true for data: URLs" do
    Deadfinder.ignore_scheme?("data:text/plain;base64,SGVsbG8sIFdvcmxkIQ==").should be_true
  end

  it "returns true for file: URLs" do
    Deadfinder.ignore_scheme?("file:///path/to/file").should be_true
  end

  it "returns true for javascript: URLs" do
    Deadfinder.ignore_scheme?("javascript:void(0)").should be_true
  end

  it "returns true for fragment-only links" do
    Deadfinder.ignore_scheme?("#top").should be_true
  end

  it "returns false for http URLs" do
    Deadfinder.ignore_scheme?("http://example.com").should be_false
  end

  it "returns false for https URLs" do
    Deadfinder.ignore_scheme?("https://example.com").should be_false
  end

  it "returns false for relative paths" do
    Deadfinder.ignore_scheme?("page.html").should be_false
  end
end
