#!/usr/bin/env ruby

require 'optparse'
require 'ostruct'

begin
  require 'bio'
rescue
  puts "\n*** You need the 'bio' gem to run #{File.basename(__FILE__)}! ***"
  puts "     %        gem install bio"
  puts "(or) %   sudo gem install bio"
end

Bio::NCBI.default_email = "abc@efg.com"

def escape(string)
  { 
    "&" => "\\&",
    "%" => "\\%",
    "{" => "\\{",
    "}" => "\\}",
  }.inject(string) do |st, (k,v)|
    st.gsub(k) {v}
  end
end

# if file is nil, then uses normal stdout
def bib_append(file=nil, &block)
  if file
    orig_stdout = $stdout
    $stdout = File.open(file,'a')
    reply = block.call
    $stdout.close
    $stdout = orig_stdout
    reply
  else
    block.call
  end
end

# returns nil if can't make a decent label
def label_from_reference(ref)
  if ref.authors.empty?.!
    first_author_last_name = ref.authors.first.split(",").first
    first_author_last_name + ref.year.to_s
  elsif ref.title
    three_word_title = ref.title.split(/\s+/)[0,3].map(&:capitalize).join.tr('^A-Za-z0-9', '')
    three_word_title + ref.year.to_s
  end
end

opt = OpenStruct.new
parser = OptionParser.new do |op|
  op.banner = "usage: #{File.basename(__FILE__)} <pubmed ID> ..." 
  op.separator "output: <bibtex formatted text>"
  op.separator "note: retrieves them all at once to be good citizen to pubmed"
  op.separator "      uses 'firstAuthorLastName+year' as default label"
  op.separator ""
  op.on("-b", "--bib-append", "append to the first .bib file found in pwd") {|v| opt.bib_append = v }
  op.on("-a", "--abstract", "include the abstract") {|v| opt.abstract = v }
  op.on("-l", "--label <String>", "use the specified label") {|v| opt.label = v }
  op.on("-q", "--quiet-label", "don't print each label to stderr") {|v| opt.quiet_label = v }
  op.on("--pmid-label", "use PMID as label (overrides -l)") {|v| opt.pmid_label = v }
end
parser.parse!

if ARGV.size == 0
  puts parser
  exit
end

# returns two parallel arrays: the labels used and the bibtex text
def entries_to_bibtexs(pmids, default_label: nil, abstract: false, pmid_label: false)
  type = 'article'
  entries = Bio::PubMed.efetch(pmids)
  ids = []
  bibtexs = entries.map do |entry|
    label = label
    medline = Bio::MEDLINE.new(entry)
    reference = medline.reference

    extra = {}
    unless label
      label = label_from_reference(reference)
    end
    label = nil if pmid_label

    extra['pmid'] = reference.pubmed
    extra['abstract'] = escape(reference.abstract) if abstract

    reference.bibtex(type, label, extra)
  end
  labels = bibtexs.map {|v| reference_to_label(v) }
  [labels, bibtexs]
end

def reference_to_label(bibtex)
  bibtex.strip[/\@article\{(\w+),/,1]
end

if __FILE__ == $0
  pmids = ARGV.dup
  bibtexs = entries_to_bibtexs(pmids, default_label: opt.label, abstract: opt.abstract, pmid_label: opt.pmid_label)

  if opt.bib_append
    bibfile = Dir["*.bib"].sort.first
    warn "no bibfile found! writing to STDOUT" unless bibfile
  end

  bib_append(bibfile) do
    (labels, bibtexs) = entries_to_bibtexs(pmids)
    labels.zip(bibtexs) do |label, bibtex|
      $stderr.puts(label) unless opt.quiet_label
      # copy the label to clipboard (may depend on a previous running instance of xclip for persistence)
      %w{clipboard primary}.each {|reg| system %Q{echo -n #{label} | xclip -selection #{reg} } }
      puts
      puts bibtex
    end
  end
end


