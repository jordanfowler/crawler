require 'optparse'
require 'ostruct'
require 'json'
require 'fileutils'
require 'active_support/all'
require 'metainspector'
require 'mida'
require 'yaml'
require 'parallel'

class Hash
  def shuffle
    Hash[self.to_a.sample(self.length)]
  end

  def shuffle!
    self.replace(self.shuffle)
  end
end

class OptionsParser
  def self.parse(args)
    options = OpenStruct.new
    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: map_webpages.rb URL [OPTIONS]"

      opts.on('-d', '--data_dir DATA_DIR',
              'Directory to store sitemaps') do |data_dir|
        options.data_dir = data_dir
      end

      opts.on('-i', '--indexer INDEXER',
              'Indexer for processing webpages') do |indexer|
        options.indexer = indexer
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

class WebpageIndexer
  attr_reader :website_uri, :options, :data_dir, :indexes_dir, :indexer_file, :caches_dir

  def initialize(url, options = OpenStruct.new)
    @website_uri = URI.parse(url)
    @options = options
    @data_dir = File.join(@options.data_dir, Date.today.to_s, @website_uri.host)
    @indexes_dir = File.join(data_dir, 'indexes')
    @indexer_file = @options.indexer
    @caches_dir = File.join(data_dir, 'caches')

    FileUtils.mkdir_p @indexes_dir
    FileUtils.mkdir_p @caches_dir
  end

  def webpage_urls
    @webpage_urls ||= JSON.parse(File.read(File.join(data_dir, 'map.json')))
  rescue
    @webpage_urls = {}
  end

  def run!
    raise "Could not find indexer: #{indexer_file}" unless File.exists?(indexer_file)
    indexer = YAML.load_file(indexer_file)

    Parallel.each(webpage_urls.shuffle, in_threads: 10) do |url, info|
      begin
        puts "Indexing #{url}"
        file_name = File.basename(url)
        file_path = File.join(indexes_dir, file_name)
        cache_path = File.join(caches_dir, "#{file_name}.html")
        cache = File.read(cache_path) if File.exists?(cache_path)

        index_webpage(url, indexer, cache) do |page_index, page_body|
          unless page_index.empty?
            File.open(file_path, 'w+') { |f| f.write(JSON.generate(page_index)) }
            File.open(cache_path, 'w+') { |f| f.write(page_body) }
          end
        end
      rescue => e
        puts e.message
      end
    end
  end

  def index_webpage(url, indexer, page_body=nil)
    page_index = {
      url: url
    }

    if page_body
      page_parsed = Nokogiri::HTML(page_body)
    else
      page = MetaInspector.new(url)
      page_body = page.to_s
      page_parsed = page.parsed
    end

    doc = Mida::Document.new(page_parsed, url)
    page_index[:microdata] = doc.each.collect(&:to_h)

    indexer.each do |key, value|
      case value
      when String
        page_index[key] = [page_parsed.css(value)].flatten.compact.collect { |n| n.text.strip.gsub("/n", ' ').gsub(/[ ]{2,}/, ' ') }
      when Hash
        if value['regex']
          regex = Regexp.new(value['regex'])
          matches = page_body.scan(regex)
          matches.each do |match|
            begin
              case value['type']
              when 'json'
                page_index[key] ||= {}
                page_index[key] = page_index[key].merge(JSON.parse(match.first))
              end
            rescue => e
              puts e.message
            end
          end
        elsif value['selector']
          selector, attribute = value['selector'], value['attribute']
          page_index[key] = [page_parsed.css(value['selector'])].flatten.compact.collect do |n|
            n[value['attribute']].to_s.strip.gsub("/n", ' ').gsub(/[ ]{2,}/, ' ')
          end
        end
      when Array
        page_index[key] = value
      end
    end
  rescue => e
    puts e.message
  ensure
    yield page_index, page_body
  end
end

options = OptionsParser.parse(ARGV)
url = ARGV.pop
raise "Missing required URL parameter" unless url
raise "Missing required DATA_DIR parameter" unless options.data_dir
raise "Missing required INDEXER parameter" unless options.indexer
mapper = WebpageIndexer.new(url, options)
mapper.run!
