#!/usr/bin/env ruby

require 'ostruct'
require 'mspire/mzml'
require 'andand'
require 'optparse'
require 'yaml'

opt = OpenStruct.new( tol: 0.1 )
parser = OptionParser.new do |op|
  op.banner = "usage: #{File.basename(__FILE__)} <file>.mzML  ms2_m/z  ..."
  op.separator ""
  op.separator "output: (one line per each ms2_m/z input)"
  op.separator "ms2_m/z: precursor_mz1, precursor_mz2, ..."
  op.separator ""
  op.on("-t", "--tol <#{opt.tol}>", Float, "tolerance for MS2 peak (in m/z units)") {|v| opt.tol = v }
end
parser.parse!

if ARGV.size == 0
  puts parser
  exit
end

(file, *ms2_mzs) = ARGV
ms2_mzs.map!(&:to_f)

Match = Struct.new(:search_ms2_mz, :found_ms2_mz, :ms2_spectrum_id, :prec_spectrum_id, :prec_mz)

matches = Mspire::Mzml.foreach(file).with_object([]) do |spectrum, matches|
  if spectrum.ms_level == 2
    ms2_mzs.each do |search_ms2_mz|
      nearest_mz = spectrum.find_nearest(search_ms2_mz)
      if (nearest_mz - search_ms2_mz).abs <= opt.tol
        matches << Match.new(
          search_ms2_mz, 
          nearest_mz, 
          spectrum.id, 
          spectrum.precursors.andand.first.spectrum_id,
          spectrum.precursor_mz
        )
      end
    end
  end
end

groups = matches.group_by(&:search_ms2_mz).map do |mz, matches|
  matches.map(&:to_h)
end

puts groups.to_yaml
