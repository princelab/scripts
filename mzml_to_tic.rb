#!/usr/bin/env ruby

require 'mspire/mzml'

if ARGV.size == 0
  puts "usage: #{File.basename($0)} <file>.mzML ..."
  puts "output: <file>.mzML: <TIC>\\n..."
  puts "        (each file TIC on a new line)"
  exit
end

ARGV.each do |file|
  puts "#{file}: " + Mspire::Mzml.foreach(file)
    .map {|spec| spec.intensities.reduce(:+) if spec.ms_level == 1 }
    .compact.reduce(:+).to_s
  $stdout.flush
end


