require 'ostruct'
require 'json'
require 'fileutils'
require 'active_support/all'
require 'metainspector'
require 'mida'
require 'yaml'
require 'parallel'
require 'json/ld'

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
    indexer = YAML.load_file(@options.indexer) if @options.indexer

    Parallel.each_with_index(webpage_urls.shuffle, in_threads: 10) do |page, index|
      url, info = page
      begin
        puts "Indexing #{url}"
        file_name = "page-#{index}"
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

    if indexer
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
    end

    # Parse Microdata
    doc = Mida::Document.new(page_parsed, url)
    page_index[:microdata] = doc.items.collect(&:to_h)

    # Parse JSON-LD
    page_index[:json_ld] = page_parsed.css('script[type="application/ld+json"]').to_a.collect { |script| JSON.parse(script) }
  rescue => e
    puts e.message
  ensure
    yield page_index, page_body
  end
end

