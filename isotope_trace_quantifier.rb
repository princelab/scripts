#!/usr/bin/env ruby

require 'optparse'
require 'mspire/mzml'
require 'ostruct'
require 'gnuplot'

Window = Struct.new(:mz_start, :mz_end, :time_start, :time_end)
Centroid = Struct.new(:scan_num, :time, :mz, :intensity)

# holds ExtractedTimePoint objects
class ExtractedChromatogram
  attr_accessor :window
  attr_accessor :centroids

  def times
    centroids.map(&:time).unique
  end

  def scan_numbers
    centroids.map(&:scan_num).unique
  end

  def intensities
    centroids.inject(0.0) {|sum,centroid| sum + centroid.intensity }
  end
end

def ensure_extension(filename, ext)
  File.extname(filename) == '' ? filename + ext : filename
end

progname = File.basename(__FILE__)

opt = OpenStruct.new( outfile: progname.chomp(".rb") + ".tsv", windows: [])
parser = OptionParser.new do |op|
  op.banner = "usage: #{progname} [OPTS] <file>.mzML ..."
  op.separator "quantifies given windows across the files"
  op.on("-o", "--outfile <#{opt.outfile}>", "name of outputfile") {|v| opt.outfile = v }
  op.on("-w", "--window <m:m:t:t>", "mz_start:mz_end:time_st:time_end", "(can call multiple times)") do |v|
    opt.windows << Window.new( *v.split(':') )
  end
  op.on("--multiplot", "plot everything together") {|v| opt.multiplot = true }
end
parser.parse!

if ARGV.size == 0 || opt.windows.size == 0
  puts parser
  exit
end

data = ARGV.each_with_object({}) do |file, data|

  range_to_ec = Hash[ opt.mz_ranges.map {|range| [range, ExtractedChromatogram.new] } ]

  Mspire::Mzml.foreach(file).each do |spectrum|
    opt.mz_ranges.each do |range|
      if spectrum.ms_level == 1
        peaks = spectrum.peaks.to_a
        indices = spectrum.select_indices(range)
        epeaks = peaks.values_at(*indices)

        epeaks.select! {|peak| peak.last > 0 } if opt.no_zeros

        if epeaks.size > 0
          range_to_ec[range] << ExtractedTimePoint.new( spectrum.id.match(/scan=(\d+)/)[1].to_i, spectrum.retention_time, epeaks)
        end
      end
    end
  end
  data[file] = range_to_ec
end

num_cols = data[data.keys.first].size
num_rows = data.size

def plotwidth(num_cols)
  num_cols * 600
end
def plotheight(num_rows)
  num_rows * 300
end

if opt.tsv_outfile
  tsv_outfile = ensure_extension(opt.tsv_outfile, ".tsv")
  File.open(tsv_outfile, 'w') do |out|
    data.each do |filename, ec_to_range|
      basename = File.basename(filename)
      ec_to_range.each do |range, ec|
        out.puts [basename, range].join(":")
        (times, intensities) = ec.ion_chromatogram
        (times, mzs) = ec.mz_view_chromatogram
        [times, intensities, mzs].each do |data|
          out.puts data.join("\t")
        end
      end
    end
  end
end

if opt.screen || opt.svg_outfile
  #File.open("tmp.gnuplot.txt", 'w') do |gp|
  Gnuplot.open do |gp|
    if opt.svg_outfile
      svg_outfile = ensure_extension(opt.svg_outfile, ".svg")
      gp << "set term svg enhanced size #{plotwidth(num_cols)},#{plotheight(num_rows)}\n"
      gp << %Q{set output "#{svg_outfile}"\n}
    end
    multiplot(gp, num_rows, num_cols) do
      data.each do |filename, ec_to_range|
        ec_to_range.each do |range, ec|
          Gnuplot::Plot.new( gp ) do |plot|
            plot.title "#{File.basename(filename)}:#{range}"
            plot.xlabel "time (s)"
            plot.ylabel "intensity"
            plot.y2label "m/z"
            plot.data << Gnuplot::DataSet.new( ec.ion_chromatogram ) do |ds|
              ds.axes = "x1y1"
              ds.with = "lines"
              ds.title = "ion intensity"
            end
            plot.data << Gnuplot::DataSet.new( ec.mz_view_chromatogram) do |ds|
              ds.axes = "x1y2"
              ds.title = "m/z"
            end
          end
          gp << "\n"
        end
      end
    end
  end
end
