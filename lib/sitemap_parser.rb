require 'nokogiri'
require 'zlib'
require 'sitemap_handler'

class SitemapParser
  def self.parse_sitemaps(url)
    puts "Parsing: #{url}"
    handler = SitemapHandler.new
    parser = Nokogiri::XML::SAX::Parser.new(handler)

    file = OpenURI.open_uri(url)
    begin
      gz = Zlib::GzipReader.new(file)
      parser.parse(gz.read)
    rescue => e
      puts "Error: #{e.message}"
      file.rewind
      parser.parse(file)
    end

    puts "Found #{handler.sitemaps.length} sitemaps"
    handler.sitemaps.each do |sitemap|
      yield(sitemap) if block_given?
    end
    return handler.sitemaps
  end

  def self.parse_pages(file_path)
    puts "Parsing: #{file_path}"
    handler = SitemapHandler.new
    parser = Nokogiri::XML::SAX::Parser.new(handler)
    file = File.new(file_path, 'r')

    begin
      gz = Zlib::GzipReader.new(file)
      parser.parse(gz.read)
    rescue => e
      puts "Error: #{e.message}"
      file.rewind
      parser.parse(file)
    end

    puts "Found #{handler.pages.length} pages"
    handler.pages.each do |pages|
      yield(pages) if block_given?
    end
    return handler.pages
  end
end
