#!/usr/bin/env ruby

require 'mspire/fasta'
require 'open-uri'

ext = ".goannot.tsv"

if ARGV.size == 0
  puts "usage: #{File.basename($0)} <file>.fasta ..."
  puts "output: <file>#{ext}"
  exit
end

chunk_size = 2
ARGV.each do |file|
  base = file.chomp(File.extname(file))
  outfile = base + ext
  
  File.open(outfile, 'w') do |out|
    Mspire::Fasta.foreach(file).each_slice(chunk_size) do |entries|
      accessions = entries.map(&:accession)

      base = 'http://www.ebi.ac.uk/QuickGO/GAnnotation?'
      params = []
      params << "protein=#{accessions.join(',')}"
      params << "format=tsv"
      params << "col=proteinID,proteinSymbol,evidence,goID,goName,aspect,ref,with,from"

      url = base + params.join("&")

      open(url) do |reply|
        out.print( reply.read )
      end
    end
  end
end
