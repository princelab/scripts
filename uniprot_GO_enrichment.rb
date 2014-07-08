#!/usr/bin/env ruby

require 'csv'
require 'optparse'
require 'ostruct'
require 'mspire/obo'

def filter_go_annotations(go_annotations, go_id_to_stanza, search_terms)
  go_annotations.select do |annot|
    name = go_id_to_stanza[annot]['name']
    search_terms.any? {|term| term === name }
  end
end

ext = ".fractionannot.tsv"
opt = OpenStruct.new( search: [] )
parser = OptionParser.new do |op|
  op.banner = "usage: #{File.basename(__FILE__)} gene_association.goa_<xxxx> go.obo <file>.tsv ..."
  op.separator "output: <file>#{ext}"
  op.separator "(where the search term and options are #commented into first line)"
  op.separator "expects <file>.tsv to be a single column of uniprot accessions"
  op.separator "uniprot_goa: http://www.ebi.ac.uk/GOA/downloads"
  op.separator "(e.g. gene_association.goa_human.gz [gunzip it first])"
  op.separator "go.obo: http://www.geneontology.org/page/download-ontology"
  op.on("-s", "--search <term>", "terms to search for (logical AND)") {|v| opt.search << v }
  op.on("-n", "--namespace <string>", "limit to specified namespace", "cellular_component, molecular_function, or biological_process") {|v| opt.namespace = v }
  op.on("--show", "show matching terms") {|v| opt.show = v }
end
parser.parse!

if ARGV.size < 3
  puts parser
  exit
end

opt.search.map! {|v| v[0] == '/' ? eval(v) : Regexp.new(Regexp.escape(v)) }

gene_association_file = ARGV.shift
go_obo = ARGV.shift

obo = Mspire::Obo.new(go_obo)
go_id_to_stanza = obo.make_id_to_stanza

uniprot_id_to_go_annotations = Hash.new {|h,k| h[k] = [] }

CSV.foreach(gene_association_file, col_sep: "\t") do |row|
  next if row[0][0] == "!"
  uniprot_id_to_go_annotations[row[1]] << row[4]
end

ARGV.each do |id_file|
  base = id_file.chomp(File.extname(id_file))
  outfile = base + ext
  ids = CSV.read(id_file, col_sep: "\t").flatten(1)
  CSV.open(outfile, 'wb', col_sep: "\t") do |csv|
    search_row = ["# " + opt.search.join(", ")]
    search_row << "namespace: #{opt.namespace}" if opt.namespace
    csv << search_row

    headers = %w(ID MATCH OUTOF)
    headers << "MATCHING" if opt.show
    csv << headers

    ids.each do |id|
      go_annotations = uniprot_id_to_go_annotations[id]
      if opt.namespace
        go_annotations.select! {|annot| go_id_to_stanza[annot]["namespace"] == opt.namespace }
      end
      matching_annots = filter_go_annotations(go_annotations, go_id_to_stanza, opt.search)
      data = [id, matching_annots.size, go_annotations.size]
      if opt.show
        data << matching_annots.map {|annot| go_id_to_stanza[annot]["name"] }.join(", ")
      end
      csv << data
    end
  end
end
