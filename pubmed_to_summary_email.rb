#!/usr/bin/env ruby

require 'shellwords'
require 'optparse'
require 'ostruct'
require 'kramdown'

begin
  require 'bio'
rescue
  puts "\n*** You need the 'bio' gem to run #{File.basename(__FILE__)}! ***"
  puts "     %        gem install bio"
  puts "(or) %   sudo gem install bio"
end

class String
  # html escape
  def html_esc
    CGI.escapeHTML(self)
  end
end

Bio::NCBI.default_email = "abc@efg.com"

opt = OpenStruct.new(abstract: true, browser: true)
parser = OptionParser.new do |op|
  op.banner = "usage: #{File.basename(__FILE__)} <pubmed ID> ..." 
  op.separator "outputs html to stdout and copies to clipboard for pasting"
  op.separator ""
  op.on("--[no-]abstract", "include the abstract (def: true)") {|v| opt.abstract = v }
  op.on("--[no-]browser", "open the text in a browser (def: true)") {|v| opt.browser = v }
end
parser.parse!

if ARGV.size == 0
  puts parser
  exit
end

def prep_authors(authors)
  authors.map! {|author| author.sub(', ', ' ') }
  authors.join(", ")
end

pubmed_base_url = "http://www.ncbi.nlm.nih.gov/pubmed/"

if __FILE__ == $0
  pmids = ARGV.dup

  entries = Bio::PubMed.efetch(pmids)
  medline_entries = entries.map {|entry| Bio::MEDLINE.new(entry) }

  lines = [] 
  lines << ""
  medline_entries.each do |entry|
    lines << " <b>#{entry.title.html_esc}</b> <i>#{entry.journal.html_esc}</i>. #{prep_authors(entry.authors).html_esc}"
    lines << "<br/>[pubmed](#{pubmed_base_url+entry.pmid})"
    lines << "" << entry.ab.html_esc if opt.abstract
    lines << ""
  end

  text = lines.join("\n")

  header = "<html><body>"
  footer = "</body></html>"

  file = ENV['HOME'] + "/tmp/pubmed_summary_#{Date.today.strftime("%Y%m%d")}.html"
  html = header + Kramdown::Document.new(text).to_html + footer
  File.write(file, html)

  cmd = "firefox -new-window #{Shellwords.escape(file)}"
  puts cmd

  system(cmd) if opt.browser

  # copy html to clipboard (depends on persistent xclip)
  #%w{clipboard primary}.each do |reg| 
  #  system %Q{echo -n #{Shellwords.escape(html)} | xclip -selection #{reg} }
  #end
end


