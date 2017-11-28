require 'uri'
require 'open-uri'
require 'fileutils'
require './sitemap_parser'
require 'optparse'
require 'parallel'

# make this editable via ENV variable
DATA_DIR="/Volumes/Houston/Dumps/scraping"

def save_sitemap(url, website_dir)
  puts "Saving #{url}"
  uri = URI.parse(url)
  sitemap = OpenURI.open_uri(uri.to_s)
  file = File.join(website_dir, uri.path.gsub('/', '-'))
  File.open(file, 'w') { |f| f.write(sitemap.read) }

  Parallel.each(SitemapParser.parse_sitemaps(url), in_threads: 10) do |sitemap_url|
    save_sitemap(sitemap_url, website_dir)
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
website_dir = File.join(DATA_DIR, "/#{website_uri.host}/sitemaps")
FileUtils.mkdir_p website_dir

puts "Processing #{website_uri.to_s}"

if website_uri.path =~ /.xml\Z/
  save_sitemap(website_uri.to_s, website_dir)
else
  website_uri.path = '/robots.txt'

  parse_robots(website_uri.to_s) do |url|
    puts "Found: #{url}"
    save_sitemap(url, website_dir)
  end  
end
