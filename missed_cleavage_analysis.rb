#!/usr/bin/env ruby

# this is a JTP rewrite of ~/lab/bin/missed_clev.rb
# may need a little debugging as it has not yet been tested after rewrite

require 'nokogiri'
require 'rubygems'
require 'gruff'
require 'yaml'

PeptideHit = Struct.new(:num_missed_cleavages, :protein_desc, :ion_score)

default_protein = "serum albumin"
if ARGV.size == 0
  puts "usage: #{File.basename(__FILE__)} <file>.xml [\"#{default_protein}\"]"
  puts ""
  puts "output: <file>.MC.yml (num_missed_cleavages => counts)"
  puts "      : <file>.MC.png (bar chart of missed cleavages)"
  exit
end

(file, prot_name) = ARGV
prot_name ||= default_protein

peptide_hits = []
File.open(file) do |io|
  Nokogiri::XML(io).xpath('//xmlns:search_hit').each do |hit|
    vals = ["./@protein_descr", 
            "./@num_missed_cleavages", 
            './/xmlns:search_score[@name="ionscore"]/@value']
    vals.map do |xpath_query|
      hit.xpath(xpath_query)
    end
    peptide_hits << PeptideHit.new(*vals)
  end
end

filtered_hits = peptide_hits.select do |hit| 
  hit.protein_desc[/#{Regexp.escape(prot_name)}/i] && hit.ion_score >= 26
end
mc_to_set = filtered_hits.group_by(&:num_missed_cleavages)
mc_to_count = Hash[ mc_to_set.map {|num_mc, hits| [num_mc, hits.size] }.sort ]

base = file.chomp(File.extname(file))
yml_file = base + ".MC.yml"
png_file = base + ".MC.png"

File.write(yml_file, mc_to_count.to_yaml)

gruff_bar = Gruff::Bar.new
gruff_bar.title = "Missed Cleavages" 

mc_to_count.each do |num_mc, count|
  gruff_bar.data(num_mc.to_s, [count])
end

gruff_bar.write(png_file)


