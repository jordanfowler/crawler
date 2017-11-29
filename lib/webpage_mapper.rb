require 'ostruct'
require 'uri'
require 'open-uri'
require 'fileutils'
require 'active_support/all'
require 'json'

class WebpageMapper
  attr_reader :website_uri, :options, :data_dir

  def initialize(url, options = OpenStruct.new)
    @website_uri = URI.parse(url)
    @options = options
    @data_dir = File.join(@options.data_dir, Date.today.to_s, @website_uri.host)
  end

  def webpage_urls
    @webpage_urls ||= JSON.parse(File.read(File.join(data_dir, 'map.json')))
  rescue
    @webpage_urls = {}
  end

  def run!
    sitemap_dir = File.join(options.data_dir, Date.today.to_s, website_uri.host, 'sitemaps')

    if options.sitemap && File.exists?(File.join(sitemap_dir, options.sitemap))
      sitemap_file = File.join(sitemap_dir, options.sitemap)
      puts "Processing #{sitemap_file}"
      process_sitemap(sitemap_file)
    else
      Dir.glob(File.join(sitemap_dir, '*')) do |sitemap_file|
        puts "Processing #{sitemap_file}"
        process_sitemap(sitemap_file)
      end
    end

    save_map_file!
  end

  def process_sitemap(sitemap_file)
    SitemapParser.parse_pages(sitemap_file) do |page_url|
      webpage_urls[page_url] ||= {}
      webpage_urls[page_url]['sitemaps'] ||= []
      unless webpage_urls[page_url]['sitemaps'].include?(sitemap_file)
        webpage_urls[page_url]['sitemaps'] << File.basename(sitemap_file)
      end
    end
  end

  def save_map_file!
    File.write(File.join(data_dir, 'map.json'), JSON.generate(@webpage_urls))
  end
end

