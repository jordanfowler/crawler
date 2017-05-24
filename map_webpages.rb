require 'uri'
require 'open-uri'
require 'fileutils'
require 'active_support/all'
require 'json'
require './sitemap_parser'
require 'parallel'

# make this editable via ENV variable
DATA_DIR="/Volumes/Houston/Dumps/scraping"

def save_page(url, dir_name)
  uri = URI.parse(url)
  index_file = File.join(DATA_DIR, "/#{uri.host}/indexes/#{dir_name}/#{uri.path.parameterize}")
  map = { url: url, file: index_file }
  map_file = File.join(DATA_DIR, "/#{uri.host}/maps/#{dir_name}/#{uri.path.parameterize}")

  puts "Saving map: #{map_file}"
  File.open(map_file, 'w') { |f| f.write(JSON.generate(map)) }
rescue => e
  puts "Failed to fetch: #{url}"
  puts e.message
end

# Main
website_uri = URI.parse(ARGV[0])
sitemap_file = File.join(DATA_DIR, "/#{website_uri.host}/sitemaps/#{ARGV[1]}")

if !ARGV[1].to_s.strip.empty? && File.exists?(sitemap_file)
  puts "Processing #{sitemap_file}"

  dir_name = File.basename(sitemap_file).parameterize
  FileUtils.mkdir_p File.join(DATA_DIR, "/#{website_uri.host}/maps/#{dir_name}")

  SitemapParser.parse_pages(sitemap_file) do |page_url|
    save_page(page_url, dir_name)
  end
else
  Dir.glob(File.join(DATA_DIR, "/#{website_uri.host}/sitemaps/*")) do |sitemap_file|
    puts "Processing #{sitemap_file}"

    dir_name = File.basename(sitemap_file).parameterize
    if File.exists?(File.join(DATA_DIR, "/#{website_uri.host}/maps/#{dir_name}.indexer.yml"))
      FileUtils.mkdir_p File.join(DATA_DIR, "/#{website_uri.host}/maps/#{dir_name}")

      Parallel.each(SitemapParser.parse_pages(sitemap_file), in_threads: 10) do |page_url|
        save_page(page_url, dir_name)
      end
    end
  end
end
