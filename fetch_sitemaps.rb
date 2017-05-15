require 'uri'
require 'open-uri'
require 'fileutils'
require './sitemap_parser'
require 'optparse'

# make this editable via ENV variable
DATA_DIR="/Volumes/Houston/Dumps/scraping"

def save_sitemap(url)
  puts "Saving #{url}"
  uri = URI.parse(url)
  sitemap = OpenURI.open_uri(uri.to_s)
  file = File.join(DATA_DIR, "/#{uri.host}/sitemaps/", uri.path.gsub('/', '-'))
  File.open(file, 'w') { |f| f.write(sitemap.read) }

  SitemapParser.parse_sitemaps(url) do |sitemap_url|
    save_sitemap(sitemap_url)
  end
rescue => e
  puts "Failed to fetch: #{url}"
  puts e.message
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

# Main
website_uri = URI.parse(ARGV[0])
puts "Processing #{website_uri.to_s}"

if website_uri.path =~ /.xml\Z/
  save_sitemap(website_uri.to_s)
else
  website_uri.path = '/robots.txt'
  FileUtils.mkdir_p File.join(DATA_DIR, "/#{website_uri.host}/sitemaps")

  parse_robots(website_uri.to_s) do |url|
    puts "Found: #{url}"
    save_sitemap(url)
  end  
end
