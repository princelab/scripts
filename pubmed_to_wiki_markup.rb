#!/usr/bin/env ruby

require 'open-uri'
require 'optparse'
require 'ostruct'

class String
  def bold
    "'''" + self + "'''"
  end

  def italic
    "''" + self + "''"
  end

  def bold_italic
    "'''''" + self + "'''''"
  end

  def italicize_journal
    (journal, rest) = self.split(".",2)
    [journal.italic, rest].join('.')
  end
end

# returns entry and shortened lines array
def get_next_entry(lines)
  entry_lines = lines.take_while {|line| line.size > 0 }
  newlines = lines[entry_lines.size..-1]
  newlines.shift  # the space
  [entry_lines.join(" "), newlines]
end

def make_citation(info, opt)
  data = [opt.list_start]
  data << info.authors
  data << info.title.bold
  data << info.citation.italicize_journal
  data << "[#{info.url} pubmed]"
  data.join(" ")
end

opt = {
  list_start: '#',
}

opts = OptionParser.new do |op|
  op.banner = "usage: #{File.basename($0)} <pubmedID> ..."
  op.separator "output: media wiki markup suitable for openwetware.org"
  op.on("-u", "--unordered-list", "output for unordered list") {|v| opt[:list_start] = '*' }
end
opts.parse!

if ARGV.size == 0
  puts opts
  exit
end

base_url = "http://www.ncbi.nlm.nih.gov/pubmed/"
ARGV.each do |pubmed_id|
  url = base_url + pubmed_id 
  url_text = url + "?format=text"
  lines = open(url_text) {|io| io.readlines }
  until lines.first[/^<pre>/]
    lines.shift
  end
  lines.shift # pre
  lines.pop # closing pre
 
  lines.map!(&:chomp)
 
  cats = [:citation, :title, :authors, :institution, :abstract, :id_info]
  vals = cats.map do |label|
    (val, lines) = get_next_entry(lines)
    val
  end
  info = Hash[cats.zip(vals)]
  info[:url] = url
  info[:citation] = info[:citation][/^\d+\.\s+(.*)/,1]

  puts make_citation(OpenStruct.new(info), OpenStruct.new(opt))
end

