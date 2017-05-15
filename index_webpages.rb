require 'json'
require 'fileutils'
require 'active_support/all'
require 'metainspector'
require 'yaml'

# make this editable via ENV variable
DATA_DIR="/Volumes/Houston/Dumps/scraping".freeze

def index_webpage(map, indexer)
  index = {}
  page = MetaInspector.new(map['url'])
  index[:page] = page.to_hash
  if indexer
    indexer.each do |key, value|
      case value
      when String
        index[key] = [page.parsed.css(value)].flatten.compact.collect { |n| n.text.strip.gsub("/n", ' ').gsub(/[ ]{2,}/, ' ') }
      when Hash
        selector, attribute = value['selector'], value['attribute']
        index[key] = [page.parsed.css(value['selector'])].flatten.compact.collect { |n| n[value['attribute']].strip.gsub("/n", ' ').gsub(/[ ]{2,}/, ' ') }
      end
    end
  end
  yield index
end

def save_index(map, index, host, folder)
  puts "Saving #{map['file']}"
  File.open(map['file'], 'w+') { |f| f.write(JSON.generate(index)) }
end

def process_from(folder, host, indexer=nil)
  if File.exists?(File.join(DATA_DIR, "/#{host}/maps/#{folder}.indexer.yml"))
    indexer = YAML.load_file(File.join(DATA_DIR, "/#{host}/maps/#{folder}.indexer.yml"))
  end

  Dir.glob(File.join(DATA_DIR, "/#{host}/maps/#{folder}/*")) do |_map|
    map = JSON.parse(File.read(_map))
    next if File.exists?(map['file'])
    puts "Processing map: #{_map}"
    index_webpage(map, indexer) do |index|
      save_index(map, index, host, folder)
    end
  end
end

# Main
website_uri = URI.parse(ARGV[0])
map_folder = File.join(DATA_DIR, "/#{website_uri.host}/maps/#{ARGV[1]}")

if !ARGV[1].to_s.strip.empty? && File.exists?(map_folder)
  FileUtils.mkdir_p File.join(DATA_DIR, "/#{website_uri.host}/indexes/#{ARGV[1]}")
  FileUtils.mkdir_p File.join(DATA_DIR, "/#{website_uri.host}/pages/#{ARGV[1]}")
  process_from(ARGV[1], website_uri.host)
else
  Dir.glob(File.join(DATA_DIR, "/#{website_uri.host}/maps/*")) do |map_folder|
    FileUtils.mkdir_p File.join(DATA_DIR, "/#{website_uri.host}/indexes/#{map_folder}")
    FileUtils.mkdir_p File.join(DATA_DIR, "/#{website_uri.host}/page/#{ARGV[1]}")
    process_from(map_folder, website_uri.host)
  end
end
