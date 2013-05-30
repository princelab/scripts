#!/usr/bin/env ruby

require 'open-uri'
require 'bio'
require 'set'

require 'mspire/digester'

if ARGV.size < 2
  puts "usage: #{File.basename(__FILE__)} acc1 acc2 [missed_cleavages]"
  puts
  puts "needs uniprot accession numbers"
  puts "outputs information about number of unique and shared tryptic peptides"
  exit
end

accessions = ARGV[0,2]
missed_cleavages = ARGV[2].to_i

puts "Missed cleavages: #{missed_cleavages}"

base_uri = 'http://www.uniprot.org/uniprot/'
ext = '.fasta'

Protein = Struct.new(:acc, :seq, :peptides)

trypsin = Mspire::Digester[:trypsin]

prots = accessions.map do |acc|
  uri = base_uri + acc + ext
  prot = Protein.new(acc, Bio::FastaFormat.new( open(uri) {|io| io.read } ).seq )
  prot.peptides = trypsin.digest(prot.seq, missed_cleavages).to_set
  prot
end

[:first, :last].each do |focus|
  prot = prots.send(focus)
  other = prots.send( (focus == :first) ? :last : :first )
  uniq = (prot.peptides - other.peptides).to_a
  puts "Unique to #{prot.acc} (#{uniq.size} of #{prot.peptides.size}):"
  puts uniq.join(" ")
  puts 
  if focus == :last
    shared = (prot.peptides & other.peptides).to_a
    puts "Shared (#{shared.size}): "
    puts shared.join(" ")
    puts
  end
end
