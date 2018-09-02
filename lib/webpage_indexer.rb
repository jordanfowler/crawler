require 'ostruct'
require 'json'
require 'fileutils'
require 'active_support/all'
require 'metainspector'
require 'mida'
require 'yaml'
require 'parallel'
require 'json/ld'
require 'digest'

### MONKEYPATCHING
class Hash
  def shuffle
    Hash[self.to_a.sample(self.length)]
  end

  def shuffle!
    self.replace(self.shuffle)
  end
end

module Mida
  class Itemprop
    private
    def extract_property_value
      element = @element.name
      if non_textcontent_element?(element)
        attribute = NON_TEXTCONTENT_ELEMENTS[element]
        if @element.attribute(attribute)
          value = @element.attribute(attribute).value
          url_attribute?(attribute) ? make_absolute_url(value) : value
        end
      else
        @element.inner_text.strip
      end
    end
  end
end
###

class WebpageIndexer
  attr_reader :website_uri, :options, :data_dir, :indexes_dir, :caches_dir

  def initialize(url, options = OpenStruct.new)
    @website_uri = URI.parse(url)
    @options = options
    @data_dir = File.join(@options.data_dir, Date.today.to_s, @website_uri.host)
    @indexes_dir = File.join(data_dir, 'indexes')
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
    indexer_dir = File.join(options.data_dir, 'indexers')

    if options.indexer
      if File.exists?(options.indexer)
        indexer_file = options.indexer
      elsif File.exists?(File.join(indexer_dir, options.indexer))
        indexer_file = File.join(indexer_dir, options.indexer)
      end
      if indexer_file
        indexer = YAML.load_file(indexer_file)
      end
    end

    Parallel.each(webpage_urls.shuffle, in_threads: 10) do |page|
      url, info = page
      begin
        puts "Indexing #{url}"
        file_name = Digest::MD5.hexdigest(url)
        file_path = File.join(indexes_dir, "#{file_name}.json")
        cache_path = File.join(caches_dir, "#{file_name}.html")
        cache = File.read(cache_path) if File.exists?(cache_path)

        index_webpage(url, cache, indexer) do |page_index, page_body|
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

  def index_webpage(url, page_body=nil, indexer=nil)
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

    # Parse with custom indexer if present
    parse_custom(url, indexer, page_index, page_body, page_parsed) if indexer
    # Parse Microdata
    parse_microdata(url, page_index, page_parsed)
    # Parse JSON-LD
    parse_json_ld(url, page_index, page_parsed)
  rescue => e
    puts e.message
  ensure
    yield page_index, page_body
  end

  protected
  def parse_json_ld(url, page_index, page_parsed)
    page_index[:json_ld] = page_parsed.css('script[type="application/ld+json"]').to_a.collect do |script|
      JSON.parse(script)
    end
  rescue => e
    puts e.message
  end

  def parse_microdata(url, page_index, page_parsed)
    doc = Mida::Document.new(page_parsed, url)
    page_index[:microdata] = doc.items.collect(&:to_h)
  rescue => e
    puts e.message
  end

  def parse_custom(url, indexer, page_index, page_body, page_parsed)
    custom_index = {}

    indexer.each do |key, value|
      case value
      when String
        custom_index[key] = [page_parsed.css(value)].flatten.compact.collect { |n| n.text.strip.gsub("/n", ' ').gsub(/[ ]{2,}/, ' ') }
      when Hash
        values = if value['regex']
          regex = Regexp.new(value['regex'])
          matches = page_body.scan(regex)
          matches.each do |match|
            begin
              case value['type']
              when 'json'
                json = match.first.gsub(/([\{,\n ]{1,})([a-zA-Z]+):/, '\1"\2":')
                custom_index[key] ||= {}
                custom_index[key] = custom_index[key].merge(JSON.parse(json))
              end
            rescue => e
              puts e.message
            end
          end
        elsif value['selector']
          selector, attribute = value['selector'], value['attribute']
          custom_index[key] = [page_parsed.css(value['selector'])].flatten.compact.collect do |n|
            if value['attribute'].present?
              n[value['attribute']].to_s.strip.gsub("/n", ' ').gsub(/[ ]{2,}/, ' ')
            else
              n.text.strip.gsub("/n", ' ').gsub(/[ ]{2,}/, ' ')
            end
          end
        end

        offset = value['offset'].to_i
        if offset > 0
          custom_index[key] = custom_index[key][offset..-1]
        end
      when Array
        custom_index[key] = value
      end
    end
  rescue => e
    puts e.message
  ensure
    page_index[:custom] = custom_index
  end
end