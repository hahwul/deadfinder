# frozen_string_literal: true

require 'nokogiri'
require 'typhoeus'
require 'zlib'
require_relative 'sitemap-parser/version'

class SitemapParser
  def initialize(url, opts = {})
    @url = url
    @options = { followlocation: true, recurse: false, url_regex: nil }.merge(opts)
  end

  def raw_sitemap
    @raw_sitemap ||= begin
      if /\Ahttp/i.match?(@url)
        request_options = @options.dup.tap { |opts| opts.delete(:recurse); opts.delete(:url_regex) }
        request = Typhoeus::Request.new(@url, request_options)
        request.on_complete do |response|
          raise "HTTP request to #{@url} failed" unless response.success?

          return inflate_body_if_needed(response)
        end
        request.run
      elsif File.exist?(@url) && @url =~ %r{[\\/]sitemap\.xml\Z}i
        File.open(@url, &:read)
      end
    end
  end

  def sitemap
    @sitemap ||= Nokogiri::XML(raw_sitemap)
  end

  def urls
    if sitemap.at('urlset')
      filter_sitemap_urls(sitemap.at('urlset').search('url'))
    elsif sitemap.at('sitemapindex')
      found_urls = []
      if @options[:recurse]
        urls = sitemap.at('sitemapindex').search('sitemap')
        filter_sitemap_urls(urls).each do |sitemap|
          child_sitemap_location = sitemap.at('loc').content
          found_urls << self.class.new(child_sitemap_location, recurse: false).urls
        end
      end
      found_urls.flatten
    else
      raise 'Malformed sitemap, no urlset'
    end
  end

  def to_a
    urls.map { |url| url.at('loc').content }
  rescue NoMethodError
    raise 'Malformed sitemap, url without loc'
  end

  private

  def filter_sitemap_urls(urls)
    return urls if @options[:url_regex].nil?

    urls.select { |url| url.at('loc').content.strip =~ @options[:url_regex] }
  end

  def inflate_body_if_needed(response)
    return response.body unless response.headers

    case response.headers['Content-Type']
    when %r{application/gzip}, %r{application/x-gzip}, %r{application/octet-stream}
      Zlib.gunzip(response.body)
    else
      response.body
    end
  end
end
