#!/usr/bin/env ruby

require 'mspire/mzml'
require 'shellwords'

MSCONVERT_CMD = "C:/pwiz/msconvert.exe"

if ARGV.size == 0
  puts "usage: #{File.basename(__FILE__)} <file>.raw ..."
  puts "output: <file>.mgf ..."
  puts ""
  puts "assumes msconvert.exe can be called: #{MSCONVERT_CMD}"
  puts "[leaves the mzML file intact]"
  exit
end

ARGV.each do |file|

  cmd = "#{MSCONVERT_CMD} -z --mzML #{Shellwords.escape(file)}"
  puts "executing: #{cmd}"
  system cmd

  pathless_basename_noext = File.basename(file, '.*')
  mzml_file = pathless_basename_noext + '.mzML'

  mgf_file = mzml_file.sub(/\.mzML$/, '.mgf')

  puts "writing to: #{mgf_file}"
  File.open(mgf_file,'w') do |out|

    Mspire::Mzml.foreach(mzml_file) do |spec|
      next unless spec.ms_level >= 2
      out.puts "BEGIN IONS"
      out.puts "TITLE=#{spec.id}"
      out.puts "PEPMASS=#{spec.precursor_mz}"
      out.puts "CHARGE=#{spec.precursor_charge}+"
      spec.peaks do |peak|
        out.puts peak.map {|v| v.round(6) }.join(' ')
      end
      out.puts "END IONS"
      out.puts ""
    end
  end
end
