#!/usr/bin/env ruby

progname = File.basename(__FILE__)

require 'optparse'
require 'ostruct'
require 'csv'
require 'stringio'
begin
  require 'andand'
  require 'mspire/mzml'
  require 'gnuplot/multiplot'
rescue
  puts "to run #{progname} you need the following gems: "
  puts "    gnuplot-multiplot (also install gnuplot the program), andand, and mspire!"
  puts "to install the gems:"
  puts "    gem install gnuplot-multiplot andand mspire"
  exit
end

def putsv(*args)
  puts *args if $VERBOSE
end

module Gnuplot
  INFINITY = 1e30
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

  # if set to a value, transform the color by that log base
  attr_accessor :color_log_base

  def initialize(filename, window, centroids=[])
    @color_log_base = nil
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

  def min_time
    centroids.first.andand.time
  end

  def max_time
    centroids.last.andand.time
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

  def mz_view_chromatogram_with_colors
    _ints = centroids.map do |centroid|
      intensity = centroid.intensity
      @color_log_base ? Math.log(intensity, @color_log_base) : intensity
    end
    [times, mzs, _ints]
  end
end

# returns xics
def sequential(mzml, xics)
  searching = xics.dup
  mzml.each do |spectrum|
    next unless spectrum.ms_level == 1
    scan_num = spectrum.id[/scan=(\d+)/,1].to_i
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

opt = OpenStruct.new( 
                     windows: [],
                     plot_size: "600,300",
                     sequential: true,
                    )
parser = OptionParser.new do |op|
  op.banner = "usage: #{progname} [OPTS] <file>.mzML ..."
  op.separator "KEY OPTIONS:"
  op.on("-q", "--quantfile <filename>", "write quantitation to given csv filename") {|v| opt.quantfile = v }
  op.on("-m", "--multiplot <filename>", "plot windows to filename as svg") {|v| opt.multiplot = v }
  op.on("-w", "--window <m:m,t:t>", "mz_start:mz_end[,time_st:time_end]", "call multiple times for many windows", "<m,t:t> to apply --mz-window", "leave off times (or end time)", "to get entire chromatogram") do |v|
    opt.windows << v
  end
  op.on("-g", "--global-mz-window <m/z>", Float, "a global m/z window", "applied to every window w/ single m/z") {|v| opt.global_mz_window = v }
  op.separator ""
  op.separator "OTHER OPTIONS:"
  op.on("--plot-size <W,H>", "width, height of each plot (#{opt.plot_size})") {|v| opt.plot_size = v }
  op.on("--color-log <Float>", Float, "use log transformed values for color") {|v| opt.color_log = v }
  op.on("--gnuplot-file <filename>", "write gnuplot commands to specified file") {|v| opt.gnuplot_file = v }
  op.on("-v", "--verbose", "talk about it") {|v| $VERBOSE = 5 }
end
parser.parse!

if ARGV.size == 0 || opt.windows.size == 0 || (!opt.quantfile && !opt.multiplot)
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
      [mz_val - opt.global_mz_window, mz_val + opt.global_mz_window]
    end
  time_vals =
    if time_string
      (start_time, end_time) = time_string.split(':').map(&:to_f)
      [start_time, end_time || Float::INFINITY]
    else
      [0, Float::INFINITY]
    end
  Window.new(Range.new(*mz_range_vals), Range.new(*time_vals) )
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
xics.each {|xic| xic.color_log_base = opt.color_log } if opt.color_log

if opt.multiplot
  putsv "plotting"
  plot_it = ->(gp) do
    gp << "set term svg noenhanced size #{width},#{height}\n"
    gp << %Q{set output "#{opt.multiplot}"\n}
    Gnuplot::Multiplot.new(gp, layout: [opt.windows.size, filenames.size]) do |mp|
      xics.group_by(&:window).each do |window, xics_by_window|
        max_group_intensity = xics_by_window.map {|xic| xic.intensities.max }.max.andand.ceil || 1.0
        min_time = window.time_range.begin
        max_time = window.time_range.end
        if max_time == Float::INFINITY
          # take the highest available time from a real data point
          # will be nil if no data points
          max_time = xics_by_window.map {|xic| xic.max_time }.max
        end

        color_range_max = 
          if opt.color_log
            Math.log(max_group_intensity, opt.color_log) 
          else
            max_group_intensity
          end

        filenames.map {|filename| xics_by_window.find {|xic| xic.filename == filename } }.each do |xic|
          Gnuplot::Plot.new(mp) do |plot|
            #plot.palette "model XYZ rgbformulae -7,-22,-23"
            plot.palette "model XYZ rgbformulae -10,-22,-23"
            plot.cbrange "[0:#{color_range_max}]"
            plot.unset "colorbox"
            plot.title "#{xic.window} #{xic.filename}"
            plot.xlabel "time (s)"
            plot.ylabel "intensity"
            plot.yrange "[0:#{max_group_intensity}]"
            plot.y2label "m/z"
            plot.ytics "nomirror"
            plot.y2tics
            plot.y2range window.mz_range.to_gplot
            plot.xrange (min_time..(max_time || Gnuplot::INFINITY)).to_gplot
            unless max_time
              plot.xtics %Q{#{min_time},#{Gnuplot::INFINITY}}
              plot.xtics %Q{add ("#{min_time}" #{min_time})}
              plot.xtics %Q{add ("Infinity" #{Gnuplot::INFINITY})}
            end
            ion_chrmt = xic.ion_chromatogram
            no_data = ion_chrmt.first.size == 0
            ion_chrmt = [[min_time],[Gnuplot::INFINITY]] if no_data
            plot.data << Gnuplot::DataSet.new( ion_chrmt ) do |ds|
              ds.axes = "x1y1"
              ds.with = "lines"
              ds.title = "ion intensity"
            end
            unless no_data
              plot.data << Gnuplot::DataSet.new( xic.mz_view_chromatogram_with_colors) do |ds|
                ds.axes = "x1y2"
                ds.title = "m/z"
                ds.with = "points pt 7 ps 0.3 palette"
              end
            end
          end
        end
      end
    end
  end
  if opt.gnuplot_file
    gp = StringIO.new
    plot_it[gp]
    gp.rewind
    File.write(opt.gnuplot_file, gp.string)
  else
    Gnuplot.open {|gp| plot_it[gp] }
  end
end

if opt.quantfile
  headers = %w(filename mz_start mz_end time_start time_end ion_count).map(&:to_sym)
  CSV.open(opt.quantfile, 'wb') do |csv|
    csv << headers
    xics.each do |xic|
      csv << headers.map {|key| xic.send(key) }
    end
  end
end
