#!/usr/bin/env ruby
# encoding: UTF-8

require 'rubygems'
require 'bundler'

begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end

require 'nokogiri'

class Nokogiri::XML::Node
  def column(column)
    self.at_css("column[name=#{column}]").content
  end
end

if ARGV.length != 2
  abort "Usage: ./jam2wp.rb [path to source XML] [path to target XML]"
end

print "Reading #{ARGV.first}... "
@source = Nokogiri::XML(File.open(ARGV.first))
puts "Done."

@target = Nokogiri.XML(File.open('template.xml'))

def text_to_html(text)
  [
    [%r{"([^"]*)"\s\(((?:http://|/|mailto:)[^\s\)]*)\)}, '<a href="\2">\1</a>'], # URLs with title
		[%r{\[([^"\]]*)\]\s\(((?:http://|/)[^\s\)]*)\)}, '<img src="\2" alt="\1" border="0"/>'], # Images
		[%r{([^"])(http://[^\s\)\]]+)}, '\1<a href="\2">\2</a>'], # plain URLs
		[%r{(\s|^|&nbsp;)/([^\s][^/<]*)/(\W|$)}, '\1<em>\2</em>\3'], # Italic
		[%r{(\s|^|&nbsp;)-=([^-=<]*)=-(\W|$)}, '\1<strike>\2</strike>\3'], # Strike (ugly but avoids clashes with other - and = handling)
		[%r{(\d*)\^(\d*)}, '\1<sup>\2</sup>'],	# Superscript
		[%r{(\s|^|&nbsp;)\*([^\s][^\*]*)\*(\W|$)}, '\1<strong>\2</strong>\3'], 	# Bold
		[%r{\\([\*/"-])}, '\1'], # Backslashes
		
    [%r{\r}, ''], # Strip carriage returns
		[%r{^([^\n]+)$}m, '<p>\1</p>'],	 # Paragraphs
		[%r{<p>-(=)+-</p>}, '<hr>'], # Horizontal rules
		[%r{<p>([^\n]+)</p>[\n\s]*<p>-*</p>}, '<h2>\1</h2>'], # Small headings
		[%r{<p>[-·•]\s?([^\n]+)</p>(\n{1}|$)}, "<ul><li>\\1</li></ul>\n"], # Lists (first pass)
		[%r{</ul>\n<ul>}, "\n"], # Lists (second pass)
		[%r{<p>(\d)\. ([^\n]+)</p>(\n{1}|$)}, '<ol type="1" start="\1"><li>\2</li></ol>' + "\n"], # Ordered lists (first pass)
		[%r{</ol>\n<ol type="1" start="\d">}, "\n"], # Ordered lists (second pass)
		[%r{</p>\n<p>([^\t])}, "<br>\n\\1"], # Line breaks
		[%r{(/?)>\[([^\s=>\]]*)=([^\s>\]]*)\]}, ' \2="\3"\1>'] # Custom property <roger=patate>
  ].each do |rule|
    text.gsub! rule[0], rule[1]
  end
  text
end

def convert_issues
  print "Parsing issues... "
  @valid_issues = []
  @draft_issues = []
  @source.css('table[name=issues]').each do |i|
    @valid_issues << i.column('id')
    @draft_issues << i.column('id') if i.column('publish') == '0'
  end
  puts "found #{@valid_issues.length} valid issues, including #{@draft_issues.length} draft issues. Done."
end

def convert_articles
  print "Parsing articles... "
  @source.css('table[name=articles]').each do |a|
    # Only import articles that are marked as current
    next unless a.column('current') == '1'
    
    # Don't import articles from non-existing issues
    next unless @valid_issues.include? a.column('issue')
    
    # Determine actual ID
    master_id = a.column('master')
    id = a.column('id')
    actual_id = if master_id == 'NULL'
      id
    else
      master_id
    end
    
    article_text = text_to_html(a.column('article'))
    
    Nokogiri::XML::Builder.with(@target.at('channel')) do |xml|
      xml.item do
        xml['wp'].post_id actual_id
        xml['dc'].creator 1
        xml['wp'].post_date a.column('timestamp')
        xml['wp'].post_type 'post'
        xml['wp'].status @draft_issues.include?(a.column('issue')) ? 'draft' : 'publish'
        xml.title a.column('title')
        xml['excerpt'].encoded a.column('blurb')
        xml['content'].encoded do
          xml.cdata article_text
        end
      end
    end
    
  end
  puts "Done."
end

def convert_pages
  print "Parsing pages... "
  @source.css('table[name=pages]').each do |p|
    # Only import articles that are marked as current
    next unless p.column('current') == '1'
  
    page_text = text_to_html(p.column('text'))
    
    Nokogiri::XML::Builder.with(@target.at('channel')) do |xml|
      xml.item do
        # xml['wp'].post_id actual_id
        xml['dc'].creator 1
        xml['wp'].post_date p.column('timestamp')
        xml['wp'].post_type 'page'
        xml['wp'].status 'publish'
        xml.title p.column('title')
        xml['content'].encoded do
          xml.cdata page_text
        end
      end
    end
    
  end
  puts "Done."
end

def convert_all
  %w(issues articles pages).each do |m|
    send "convert_#{m}"
  end
end

convert_all

print "Writing #{ARGV[1]}... "
File.open(ARGV[1], 'w') { |f| f.write(@target.to_xml) }
puts "Done."