require 'ostruct'
require 'uri'
require 'open-uri'
require 'fileutils'
require 'parallel'
require 'digest'
require 'sitemap_parser'
require 'json'

class SitemapFetcher
  attr_reader :website_uri, :options, :data_dir, :map

  def initialize(url, options = OpenStruct.new)
    @website_uri = URI.parse(url)
    @options = options
    @data_dir = File.join(@options.data_dir, Date.today.to_s, @website_uri.host)
    @map = {}
  end

  def run!
    sitemaps_dir = File.join(data_dir, 'sitemaps')
    FileUtils.mkdir_p sitemaps_dir

    puts "Processing #{website_uri.to_s}"

    if website_uri.path =~ /.xml\Z/
      save_sitemap(website_uri.to_s, sitemaps_dir)
    else
      website_uri.path = '/robots.txt'

      parse_robots(website_uri.to_s) do |url|
        save_sitemap(url, sitemaps_dir)
      end  
    end

    save_map_file!
    yield map if block_given?
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

  def save_sitemap(url, dir)
    puts "Found sitemap: #{url}"
    sitemap = OpenURI.open_uri(url)
    digest = Digest::MD5.hexdigest(url)
    file = File.join(dir, digest)
    File.open(file, 'w') { |f| f.write(sitemap.read) }
    map[digest] = url

    Parallel.each(SitemapParser.parse_sitemaps(url), in_threads: 10) do |sitemap_url|
      save_sitemap(sitemap_url, dir)
    end
  rescue => e
    puts "Failed to fetch: #{url}"
    puts e.message
  end

  def save_map_file!
    File.write(File.join(data_dir, 'sitemaps_map.json'), JSON.generate(map))
  end
end
