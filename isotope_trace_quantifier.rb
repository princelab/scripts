#!/usr/bin/env ruby

require 'optparse'
require 'mspire/mzml'
require 'ostruct'
require 'gnuplot/multiplot'
require 'csv'

def putsv(*args)
  puts *args if $VERBOSE
end

class Range
  def to_gplot
    "[#{self.begin}:#{self.end}]"
  end
end

Window = Struct.new(:mz_range, :time_range) do
  def to_s
    "#{mz_range.begin}:#{mz_range.end}mz,#{time_range.begin}:#{time_range.end}(s)"
  end
end
Centroid = Struct.new(:scan_num, :time, :mz, :intensity) do
  def to_s
    "<#{scan_num}:#{time}(s) #{mz}m/z #{intensity}>"
  end
end

# holds ExtractedTimePoint objects
class ExtractedChromatogram
  attr_accessor :filename
  attr_accessor :window
  attr_accessor :centroids
  attr_accessor :mz_range
  attr_accessor :time_range

  def initialize(filename, window, centroids=[])
    @filename, @window, @centroids = filename, window, centroids
  end

  def time_range
    window.time_range
  end

  def mz_range
    window.mz_range
  end

  def mz_start
    mz_range.begin
  end

  def mz_end
    mz_range.end
  end

  def time_start
    time_range.begin
  end

  def time_end
    time_range.end
  end

  def times
    centroids.map(&:time)
  end

  def scan_numbers
    centroids.map(&:scan_num)
  end

  # the total ion counts
  def ion_count
    centroids.inject(0.0) {|sum,centroid| sum + centroid.intensity }
  end

  def intensities
    centroids.group_by(&:scan_num).map do |scan_num, cents|
      cents.inject(0.0) {|sum,obj| sum + obj.intensity }
    end
  end

  def mzs
    centroids.map(&:mz)
  end

  def ion_chromatogram
    [times.uniq, intensities]
  end

  def mz_view_chromatogram
    [times, mzs]
  end
end

def ensure_extension(filename, ext)
  File.extname(filename) == '' ? filename + ext : filename
end

def scan_num(id)
  id[/scan=(\d+)/,1].to_i
end

# returns xics
def sequential(mzml, xics)
  searching = xics.dup
  mzml.each do |spectrum|
    next unless spectrum.ms_level == 1
    scan_num = scan_num(spectrum.id)
    rt = spectrum.retention_time
    finished = []
    matching = searching.select do |xic|
      if xic.time_range === rt
        true
      else
        finished << xic if rt > xic.time_range.end
        false
      end
    end

    matching.each do |xic|
      indices = spectrum.select_indices(xic.mz_range)
      centroids = spectrum.mzs.values_at(*indices).
        zip(spectrum.intensities.values_at(*indices)).
        map do |mz, int|
          Centroid.new(scan_num, rt, mz, int)
        end
      xic.centroids.push(*centroids)
    end

    searching -= finished
    if searching.size == 0
      putsv "no more windows to match at rt(s): #{rt}"
      break 
    end
  end
  xics
end

progname = File.basename(__FILE__)

outfilebase = progname.chomp(".rb")
opt = OpenStruct.new( 
                     outfile:  outfilebase + ".csv", 
                     windows: [],
                     plot_size: "600,300",
                    )
parser = OptionParser.new do |op|
  op.banner = "usage: #{progname} [OPTS] <file>.mzML ..."
  op.separator "quantifies given windows across the files"
  op.on("-o", "--outfile <#{opt.outfile}>", "name of outputfile") {|v| opt.outfile = v }
  op.on("-w", "--window <m:m,t:t>", "mz_start:mz_end,time_st:time_end", "call multiple times for many windows", "<m,t:t> to apply --mz-window") do |v|
    opt.windows << v
  end
  op.on("-m", "--mz-window <m/z>", Float, "a global m/z window") {|v| opt.mz_window = v }
  op.on("-s", "--sequential", "do a sequential search instead of binary search", "can be faster if lots of windows") {|v| opt.sequential = v }
  op.on("--multiplot", "plot everything together to <#{outfilebase}>.svg") {|v| opt.multiplot = outfilebase + ".svg" }
  op.on("--plot-size <W,H>", "width, height of each plot") {|v| opt.plot_size = v }
  op.on("-v", "--verbose", "talk about it") {|v| $VERBOSE = 5 }
end
parser.parse!

if ARGV.size == 0 || opt.windows.size == 0
  puts parser
  exit
end

opt.windows.map! do |string|
  (mz_string, time_string) = string.split(',')
  mz_range_vals = 
    if mz_string[':']
      mz_string.split(':').map(&:to_f)
    else
      mz_val = mz_string.to_f
      [mz_val - opt.mz_window, mz_val + opt.mz_window]
    end
  Window.new(Range.new(*mz_range_vals), Range.new(*time_string.split(':').map(&:to_f)) )
end

opt.plot_size = opt.plot_size.split(',').map(&:to_i)

filenames = ARGV.dup

xic_set = filenames.map do |filename|
  xics = opt.windows.map {|window| ExtractedChromatogram.new( filename, window ) }
  Mspire::Mzml.open(filename) do |mzml|
    if opt.sequential
      sequential(mzml, xics)
    else
      abort "haven't implemented binary search yet, use --sequential for now"
    end
  end
end

width = filenames.size * opt.plot_size.first
height = opt.windows.size * opt.plot_size.last

xics = xic_set.flatten(1)

if opt.multiplot
  putsv "plotting"
  Gnuplot.open do |gp|
    gp << "set term svg noenhanced size #{width},#{height}\n"
    gp << %Q{set output "#{opt.multiplot}"\n}
    Gnuplot::Multiplot.new(gp, layout: [opt.windows.size, filenames.size]) do |mp|
      xics.group_by(&:window).each do |window, xics_by_window|
        max_group_intensity = xics_by_window.map {|xic| xic.intensities.max }.max.ceil
        filenames.map {|filename| xics_by_window.find {|xic| xic.filename == filename } }.each do |xic|
          Gnuplot::Plot.new(mp) do |plot|
            plot.title "#{xic.window} #{xic.filename}"
            plot.xlabel "time (s)"
            plot.ylabel "intensity"
            plot.yrange "[0:#{max_group_intensity}]"
            plot.y2label "m/z"
            plot.ytics "nomirror"
            plot.y2tics
            plot.y2range window.mz_range.to_gplot
            plot.data << Gnuplot::DataSet.new( xic.ion_chromatogram ) do |ds|
              ds.axes = "x1y1"
              ds.with = "lines"
              ds.title = "ion intensity"
            end
            plot.data << Gnuplot::DataSet.new( xic.mz_view_chromatogram) do |ds|
              ds.axes = "x1y2"
              ds.title = "m/z"
              ds.with = "points pt 7 ps 0.25"
            end
          end
        end
      end
    end
  end
end

if opt.outfile
  headers = %i(filename mz_start mz_end time_start time_end ion_count)
  CSV.open(opt.outfile, 'wb') do |csv|
    csv << headers
    xics.each do |xic|
      csv << headers.map {|key| xic.send(key) }
    end
  end
end
