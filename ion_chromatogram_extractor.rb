#!/usr/bin/env ruby

require 'optparse'
require 'mspire/mzml'
require 'ostruct'
require 'gnuplot'

ExtractedTimePoint = Struct.new(:spectrum_id, :scan_num, :time, :peaks) do

end
# holds ExtractedTimePoint objects
class ExtractedChromatogram < Array 
  # return [times, intensities]; sums the intensities.
  def ion_chromatogram
    times = []
    intensities = []
    self.each do |etp|
      times << etp.time
      intensities << etp.peaks.inject(0.0) {|sum, peak| sum + peak.last }
    end
    [times, intensities]
  end

  def mz_view_chromatogram
    times = []
    mzs = []
    self.each do |etp|
      etp.peaks.each do |peak|
        times << etp.time
        mzs << peak.first
      end
    end
    [times, mzs]
  end
end

# yields the io object for writing
def multiplot(io, num_rows, num_cols, &block)
  io << "set size 1,1\n"
  io << "set origin 0,0\n"
  io << "set multiplot layout #{num_rows},#{num_cols} rowsfirst scale 1.0,1.0\n"
  block.call
  io << "unset multiplot\n"
end

def ensure_extension(filename, ext)
  File.extname(filename) == '' ? filename + ext : filename
end


opt = OpenStruct.new
parser = OptionParser.new do |op|
  op.banner = "usage: #{File.basename(__FILE__)} <file>.mzML ..."
  op.separator "plots to screen"
  op.on("-m", "--mz-ranges <s:e,...>", "start:end,start:end,... ") do |v| 
    opt.mz_ranges = v.split(',').map {|se_st| Range.new( *se_st.split(':').map(&:to_f) ) }
  end
  op.on("--screen", "plot to screen") {|v| opt.screen = v }
  op.on("-s", "--svg-outfile <file>", "writes a plot as svg") {|v| opt.svg_outfile = v }
  op.on("-t", "--tsv-outfile <file>", "writes data to tsv file") {|v| opt.tsv_outfile = v }
  op.on("-n", "--no_zeros", "remove zero values") {|v| opt.no_zeros = v }
end
parser.parse!


if ARGV.size == 0
  puts parser
  exit
elsif !opt.mz_ranges
  abort "need at least one mz range (-m)"
elsif !(opt.svg_outfile || opt.tsv_outfile || opt.screen)
  abort "need either --screen || --svg-outfile || --tsv-outfile" 
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
          range_to_ec[range] << ExtractedTimePoint.new( spectrum.id, spectrum.id.match(/scan=(\d+)/)[1].to_i, spectrum.retention_time, epeaks)
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
            plot.ytics "nomirror"
            plot.y2tics
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
