#!/usr/bin/env ruby

require 'open-uri'

if ARGV.size == 0
  puts "usage: #{File.basename(__FILE__)} 1 2 ..."
  puts "     : #{File.basename(__FILE__)} all"
  puts "     : #{File.basename(__FILE__)} X-Y"
  puts "downloads those lipid classes from lipipmaps"
  puts "takes a range or individual classes or the keyword 'all'"

  puts "a slightly different format (better exact masses) can be found here:"
  puts "  http://www.lipidmaps.org/downloads/index.html"
  puts "[there are a couple different LM_ID's between the two files"
  puts "with the script method coming out with a hundred more lipids"
  puts "which is probably due to it getting the latest lipids]"
  exit
end

classes = 
  if ARGV.size == 1
    if ARGV.first =~ /all/i
      (1..8).to_a
    elsif ARGV.first.include?('-')
      (Range.new *ARGV.first.split('-')).to_a
    else
      ARGV.to_a.map(&:to_i)
    end
  else
    ARGV.to_a.map(&:to_i)
  end
classes.sort!

  
# this should work:
base_url = "http://www.lipidmaps.org/data/structure/LMSDSearch.php?Mode=ProcessTextSearch&OutputMode=File"

# this downloads the whole database (but not certain lipids):
#"http://www.lipidmaps.org/data/structure/LMSDSearch.php?Mode=ProcessStrSearch&OutputMode=File&OutputType=TSV&OutputColumnHeader=Yes"

string = classes.map do|cclass|
  additional_param = "&CoreClass=#{cclass}"
  url = base_url + additional_param
  puts "downloading: #{url}" ; $stdout.flush
  open(url) {|io| io.read }
end.reduce(:+)

uniq_string = string.split(/\r?\n/).uniq.join("\n")

base_outfile = "lipidmaps_#{Time.now.strftime("%Y%m%d")}"
ext = if ARGV.first == 'all'
        "_all.tsv"
      else
        "_classes_#{classes.join('_')}.tsv"
      end
output_file = base_outfile + ext
File.write output_file, uniq_string
puts "wrote #{output_file}"
