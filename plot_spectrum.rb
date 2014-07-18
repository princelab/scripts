#!/usr/bin/env ruby

require 'gnuplot'
require 'mspire/mzml'
require 'optparse'
require 'ostruct'

opt = OpenStruct.new
parser = OptionParser.new do |op|
  op.banner = "usage: #{File.basename(__FILE__)} <file>.mzML <spectrum_num> ..."
  op.separator ""
  op.on("-i", "--identifiers", "consider id's, not spectrum indices") {|v| opt.identifiers = v }
  op.on("-m", "--mz-range <start:stop>", "give start and stop m/z vals") {|v| opt.mz_range = Range.new(*opt.mz_range = v.split(':').map(&:to_f)) }
  op.on("-s", "--svg", "plot to svg") {|v| opt.svg = v }
end
parser.parse!

if ARGV.size < 2
  puts parser
  exit
end

mzml_file = ARGV.shift
spectra_indices = ARGV.dup
spectra_indices.map!(&:to_i) unless opt.identifiers

Gnuplot.open do |gp|
  spectra = Mspire::Mzml.open(mzml_file) do |mzml|
    spectra_indices.each do |i|
      spectrum = mzml[i]
      abort "no spectrum at #{i}" unless spectrum
      spectral_data = 
        if opt.mz_range

          indices = spectrum.select_indices(opt.mz_range) 
          [spectrum.mzs.values_at(*indices), spectrum.intensities.values_at(*indices)]
        else
          [spectrum.mzs, spectrum.intensities]
        end
      abort "no data inside given range" unless spectral_data.first.size > 0

      filename = "spectrum_#{i}.svg"
      Gnuplot::Plot.new(gp) do |plot|
        plot.terminal "svg size 800,200" if opt.svg
        plot.output filename if opt.svg
        plot.title "spectrum_#{i} mslevel:#{spectrum.ms_level}"
        plot.xrange "[#{opt.mz_range.begin}:#{opt.mz_range.end}]"
        plot.xlabel "m/z"
        plot.ylabel "intensity"
        plot.data << Gnuplot::DataSet.new( spectral_data ) do |ds|
          ds.with = (spectrum.profile? ? "lines" : "impulses")
          ds.notitle
        end
      end
    end
  end
end
