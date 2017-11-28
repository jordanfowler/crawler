require 'optparse'
require 'ostruct'
require 'uri'
require 'open-uri'
require 'fileutils'
require 'parallel'
require 'pp'
require './sitemap_parser'

class OptionsParser
  def self.parse(args)
    options = OpenStruct.new
    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: fetch_sitemaps.rb URL [OPTIONS]"

      opts.on('-d', '--data_dir DATA_DIR',
              'Directory to store sitemaps') do |data_dir|
        options.data_dir = data_dir
      end

      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end
    end
    opt_parser.parse!(args)
    options
  end
end

class SitemapFetcher
  attr_reader :website_uri, :options, :data_dir

  def initialize(url, options = OpenStruct.new)
    @website_uri = URI.parse(url)
    @options = options
    @data_dir = File.join(@options.data_dir, Date.today.to_s, @website_uri.host, 'sitemaps')
  end

  def run!
    FileUtils.mkdir_p data_dir

    puts "Processing #{website_uri.to_s}"

    if website_uri.path =~ /.xml\Z/
      save_sitemap(website_uri.to_s, data_dir)
    else
      website_uri.path = '/robots.txt'

      parse_robots(website_uri.to_s) do |url|
        puts "Found: #{url}"
        save_sitemap(url, data_dir)
      end  
    end
  end

  def parse_robots(url)
    sitemaps = []
    OpenURI.open_uri(url).each_line do |line|
      if line =~ /Sitemap\:[ ]{0,}([^ ]+)/i
        sitemap = $1.to_s.strip
        yield(sitemap) if block_given?
        sitemaps << sitemap
      end
    end
    return sitemaps
  end

  def save_sitemap(url, data_dir)
    puts "Saving #{url}"
    uri = URI.parse(url)
    sitemap = OpenURI.open_uri(uri.to_s)
    file = File.join(data_dir, uri.path)
    dir = file.sub(File.basename(file), '')
    FileUtils.mkdir_p(dir)
    File.open(file, 'w') { |f| f.write(sitemap.read) }

    Parallel.each(SitemapParser.parse_sitemaps(url), in_threads: 10) do |sitemap_url|
      save_sitemap(sitemap_url, data_dir)
    end
  rescue => e
    puts "Failed to fetch: #{url}"
    puts e.message
  end
end

options = OptionsParser.parse(ARGV)
url = ARGV.pop
raise "Missing required URL parameter" unless url
raise "Missing required DATA_DIR parameter" unless options.data_dir
SitemapFetcher.new(url, options).run!
