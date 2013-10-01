#!/usr/bin/env ruby

require 'rubabel'
require 'msplinter'
require 'mspire/spectrum'
require 'mspire/peaklist'
require 'mspire/tagged_peak'
require 'andand'
require 'gnuplot'

if ARGV.size == 0
  puts "usage: #{File.basename(__FILE__)} lmid <file>.mgf"
  exit
end

# LMGP02010036
#  'CCCCCCCCCCCCCCCCCC(=O)OCC(COP(=O)(O)OCCN)OC(=O)CCCCCCCC=CCCCCCCCC'

(lipid_id, mgf_file) = ARGV
#mol = Rubabel[lipid_id, :lmid]
mol = Rubabel[lipid_id]
csmiles = 'CCCCCCCCCCCCCCCCCC(=O)OC[C@@H](OC(=O)CCCCCCC/C=C\CCCCCCCC)COP(=O)(OCCN)O'

p mol.fragment


class MascotSpectrum
  include Mspire::SpectrumLike
  attr_accessor :title, :rtinseconds, :pepmass, :pepintensity
end

spectra = []
current_spectrum = nil
IO.foreach(mgf_file) do |line|
  line.chomp!
  if line == 'BEGIN IONS'
    current_spectrum = MascotSpectrum.new([[],[]])
  elsif line == 'END IONS'
    current_spectrum.rtinseconds = current_spectrum.rtinseconds.to_f
    current_spectrum.pepintensity = current_spectrum.pepmass.split(" ").last.andand.to_f
    current_spectrum.pepmass = current_spectrum.pepmass.split(" ").first.to_f
    spectra << current_spectrum
  elsif md=line.match(/(\w+)=(.*)/)
    current_spectrum.send(md[1].downcase + '=', md[2])
  elsif line.include?(' ')
    (mz, int) = line.split(' ').map(&:to_f)
    current_spectrum.mzs << mz 
    current_spectrum.intensities << int
  else
    puts "weirdline: #{line}"
  end
end

#spectrum = Mspire::Peaklist.merge(spectra.map(&:to_peaklist), bind_width: 0.1, bin_unit: :amu, :split => :greedy_y)
spectrum = Mspire::Peaklist.merge(spectra.map(&:to_peaklist), bin_width: 1500).to_spectrum

Gnuplot.open do |gp|
  Gnuplot::Plot.new(gp) do |plot|
    plot.title "hello"
    plot.data << Gnuplot::DataSet.new(spectrum.data_arrays) do |ds|
      ds.with = 'impulses'
    end
  end
end
