#!/usr/bin/env ruby

# https://gist.github.com/jesusabdullah/4044049
# typical sequence if citations:
#   xelatex
#   biber
#   xelatex
#   xelatex
#
# note that xelatex is superior to pdflatex
# note that biber is superior to bibtex

require 'shellwords'
require 'optparse'
require 'ostruct'

ENV_VARS = {
  'TEXMFHOME' => 'texmf',
  'BSTINPUTS' => 'texmf/tex/bibtex/bib',
}

AUX_EXTS = %w(.bbl .blg .log .aux .out .toc -blx.bib .bcf .run.xml)

# bastardize the string class for easy file manipulation
class String
  def unlink
    if File.exist?(self)
      File.unlink(self) 
      putsv "deleting: #{self}"
    end
  end

  def escape
    Shellwords.escape(self)
  end

  def rename(newname)
    if File.exist?(self)
      File.rename(self, newname)
    end
  end
end

def delete_auxs(base, exts=AUX_EXTS)
  exts.each do |ext| 
    [nil,0,1,2].each do |n|
      unless $DRY
        base.+("#{ext}#{n}").unlink
      end
    end
  end
end

def runv(*args)
  putsv "running: #{args.join(' ')}"
  unless $DRY
    system *args
  end
end

def putsv(*args)
  puts *args if $VERBOSE
end

$DRY = false
opt = OpentStruct.new(biber: true)

parser = OptionParser.new do |op|
  op.banner = "usage: #{File.basename(__FILE__)} [OPTS] <file>.tex"
  op.separator "output: <file>.pdf"
  op.separator ""
  op.separator "runs xelatex"
  op.separator "runs xelatex/bibtex/xelatex/xelatex if .bib file exists "
  op.separator ""
  op.separator "note: "
  op.separator "  * removes <file>.pdf before running"
  op.separator "  * removes auxiliary files: <file>.{#{AUX_EXTS.join(',')}}"
  op.separator ""
  op.separator "note: stalls if there are errors -- check <file>.log or .log{1-3}"
  op.separator ""
  op.separator "opts:"
  op.on("--latex-verbose", "spit out latex messages") {|v| opt.latex_verbose = v }
  op.on("--no-delete-pdf", "don't delete the pdf file before") {|v| opt.no_delete_pdf = v }
  op.on("-v", "--verbose", "what is happening") {|v| $VERBOSE = 3 }
  op.on("--finished", "just tell me when finished") {|v| $FINISHED = true }
  op.on("--dirty", "leave auxiliary files") {|v| opt.dirty = v }
  op.on("--delete", "just delete auxiliary files") {|v| opt.delete = v }
  op.on("--dry", "don't run anything") {|v| $DRY = v ; $VERBOSE = 3 }
  op.on("--bibtex", "use bibtex instead of biber") {|v| opt.biber = false }
  op.on("--env", "print env variable export line and exit") {|v| opt.env = v }
end
parser.parse!

if opt.env
  puts ENV_VARS.map {|k,v| "export #{k}=#{v}" }.join("; ")
  exit
end

if ARGV.size == 0
  puts opts
  exit
end


file = ARGV.shift

quiet = opt.latex_verbose ? nil : ">/dev/null 2>&1"

latexdir = File.expand_path(File.dirname(file))
putsv "changing to #{latexdir}"

ENV_VARS.each do |key, val|
  ENV[key] = val unless $DRY
  puts "export #{key}=#{val}" if $VERBOSE
end

Dir.chdir(latexdir) do |latexdir|

  basename = File.basename(file)
  base = basename.chomp(File.extname(basename))
  pdfname = base + ".pdf"
  logname = base + ".log"
  bibname = base + ".bib"
  tocname = base + ".toc"

  putsv "cleaning up auxiliary files"
  delete_auxs(base)
  exit if opt.delete

  pdfname.unlink unless opt.no_delete_pdf
  logname.unlink

  xelatex_cmd = ["xelatex", basename.escape, quiet].compact.join(' ')

  2.times{ runv xelatex_cmd }

  if File.exist?(bibname)
    logname.rename logname + "0"
    runv ["bibtex", base.escape, quiet].compact.join(" ")
    runv xelatex_cmd
    logname.rename logname + "1"
    runv xelatex_cmd
    logname.rename logname + "2"
  end

  unless opt.dirty
    putsv "cleaning up auxiliary files"
    delete_auxs(base)
  end
  puts "finished!" if ($VERBOSE || $FINISHED)
end
