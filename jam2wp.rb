#!/usr/bin/env ruby

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

if ARGV.length != 2
  abort "Usage: ./jam2wp.rb [path to source XML] [path to target XML]"
end

print "Reading #{ARGV.first}... "
source = Nokogiri::XML(File.open(ARGV.first))
puts "Done."

target = Nokogiri.XML(File.open('template.xml'))

print "Parsing articles... "
source.css('table[name=articles]').each do |row|
  # Only import articles that are marked as current
  next unless row.at_css('column[name=current]').content == '1'
  
  # Determine actual ID
  master_id = row.at_css('column[name=master]').content
  id = row.at_css('column[name=id]').content
  actual_id = if master_id == 'NULL'
    id
  else
    master_id
  end
  
  new_article = Nokogiri::XML::Node.new "item", target
  new_article.add_child(Nokogiri::XML::Node.new 'wp:post_id', target).content = actual_id
  
  {
    'title'     => 'title',
    'timestamp' => 'wp:post_date',
    'blurb'     => 'excerpt:encoded'
  }.each do |old_column, new_column|
    new_article.add_child(Nokogiri::XML::Node.new new_column, target).content = row.at_css("column[name=#{old_column}]").content
  end
  
  target.at_css('channel').add_child(new_article)
end
puts "Done."

print "Writing #{ARGV[1]}... "
File.open(ARGV[1], 'w') { |f| f.write(target.to_xml) }
puts "Done."