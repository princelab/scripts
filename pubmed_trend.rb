#!/usr/bin/env ruby

require 'optparse'
require 'ostruct'
require 'gnuplot'
require 'bio'

Bio::NCBI.default_email = "abc@def.ghi.com"

def counts(query, year)
  query_w_date = "#{year}[PPDAT] " + query
  url_query = %Q{http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&rettype=count&term=#{CGI.escape(query_w_date)}}
  reply = open(url_query) {|io| io.read }
  reply.match(/<Count>(\d*)<\/Count>/)[1].to_i
end

opt = OpenStruct.new(years: [2000, 2013])
parser = OptionParser.new do |op|
  op.banner = "usage: #{File.basename($0)} 'query' ..."
  op.on("-y", "--years <start:stop>", "a range of years, default: #{opt.years.join(':')}") {|v| opt.years = v.split(':').map(&:to_i) }
  op.on("-f", "--fraction", "plot fraction of all pubmed hits") {|v| opt.fraction = v }
  op.on("-o", "--order", "order by last value") {|v| opt.order = v }
  op.on("-l", "--log", "log base 10 of counts") {|v| opt.log = v }
  op.on("--yrange <start:end>", "set yrange") {|v| opt.yrange = '[' + v + ']' }
  op.on("--smooth <years>", "smooth the data by x years" ) {|v| opt.smooth = v.to_i }
end
parser.parse!

if ARGV.size == 0
  puts parser
  exit
end

queries = ARGV.dup
years = Range.new(*opt.years).to_a

responses = queries.map do |query|
  years.map do |year|
    counts query, year
  end
end

q_r_pairs = queries.zip(responses).to_a
xlabel = "years"

if opt.smooth
  q_r_pairs.map! do |query,response|
    new_years = []
    new_responses = years.zip(response).each_cons(opt.smooth).map do |year_response_pairs|
      year_response_pairs.map(&:last).reduce(:+) / year_response_pairs.size
    end
    [query, new_responses]
  end
  years = years.each_cons(opt.smooth).map {|them_years| them_years.last }
  xlabel << " (avg with prev #{opt.smooth-1})"
end

if opt.order
  q_r_pairs = q_r_pairs.sort_by {|query, response| response.last }.reverse
end

# "<?xml version=\"1.0\" ?>\n<!DOCTYPE eSearchResult PUBLIC \"-//NLM//DTD esearch 20060628//EN\" \"http://eutils.ncbi.nlm.nih.gov/eutils/dtd/20060628/esearch.dtd\">\n<eSearchResult>\n\t<Count>0</Count>\n</eSearchResult>\n

Gnuplot.open do |gp|
  Gnuplot::Plot.new( gp ) do |plot|

    plot.title  "pubmed hits"
    plot.xlabel xlabel
    plot.ylabel "num pubmed hits"
    plot.size '0.6,0.6'
    plot.yrange(opt.yrange) if opt.yrange

    q_r_pairs.each do |query, response|
      response = response.map {|v| Math.log(v, 10) } if opt.log
      plot.data << Gnuplot::DataSet.new( [years, response] ) do |ds|
        ds.with = "linespoints"
        ds.title = query
      end
    end
  end
end
