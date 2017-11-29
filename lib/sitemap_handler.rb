require 'nokogiri'

class SitemapHandler < Nokogiri::XML::SAX::Document
  attr_reader :sitemap_index, :sitemaps, :pages

  def initialize
    @match_count = 0

    @sitemaps = []

    @sitemap_index = false
    @sitemap = false
    @loc = false

    @pages = []
  end

  def start_element(name, attrs = [])
    if name == 'sitemapindex'
      @sitemap_index = true 
    end

    if name == 'sitemap'
      @sitemap = true
    end

    if name == 'loc'
      @loc = true
      @cloc = ''
    end
  end

  def characters(string)
    if @loc
      @cloc += string.strip
    end
  end

  def cdata_block(string)
    if @loc
      @cloc += string.sub(/\A\s*\<\!\[CDATA\[(.*)\]\]\s*\>\Z/, '\1').strip
    end
  end

  def end_element(name)
    if name == 'sitemapindex'
      @sitemap_index = false
    end

    if name == 'sitemap'
      @sitemap = false
    end

    if name == 'loc'
      if @sitemap_index and @sitemap or @cloc =~ /\.xml/
        @sitemaps << @cloc
      else
        @pages << @cloc
      end

      @loc = false
    end
  end
end