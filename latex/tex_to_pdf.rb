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

# bastardize the string class for easy file manipulation
class String

  def escape
    Shellwords.escape(self)
  end

end


# assumes it is in the directory with the latex file
class LatexRunner

  ENV_VARS = {
    'TEXMFHOME' => 'texmf',
    'BSTINPUTS' => 'texmf/tex/bibtex/bib',
  }
  
  AUX_EXTS = %w(.bbl .blg .log .aux .out .toc -blx.bib .bcf .run.xml .bib.blg)

  def rename(old, newname)
    if File.exist?(old)
      putsv "renaming #{old} -> #{newname}"
      File.rename(old, newname) unless @dry
    end
  end

  def unlink(file)
    if File.exist?(file)
      putsv "unlinking: #{file}"
      File.unlink(file) unless @dry
    end
  end

  def putsv(*args)
    puts *args if @verbose
  end

  # returns any output suppression string, or nil
  def quiet
    if @suppress_output
      ">/dev/null 2>&1"
    end
  end

  def set_env_vars
    ENV_VARS.each do |key, val|
      ENV[key] = val unless @dry
      puts "export #{key}=#{val}" if @verbose
    end
  end

  def initialize(texfile, cmd: "xelatex", suppress_output: true, dry: false, verbose: false, bibcreator: "biber", &block)
    @cmd = cmd
    @latexdir = File.expand_path(File.dirname(texfile))
    texfile_b = File.basename(texfile)
    @suppress_output = suppress_output
    @base = texfile_b.chomp(File.extname(texfile_b))
    @dry = dry
    @cnt = 0
    @verbose = verbose
    @bibcreator = bibcreator
    change_to_latexdir(&block) if block
  end

  def change_to_latexdir(&block)
    putsv "changing to #{@latexdir}" unless Dir.pwd == @latexdir
    Dir.chdir(@latexdir) do
      set_env_vars
      block.call(self)
    end
  end

  def delete_pdf
    unlink pdfname
  end

  %w(tex pdf log bib toc).each do |type|
    define_method( type + "name" ) { @base + ".#{type}" }
  end

  def process(num)
    run(num)
    if File.exist?(bibname)
      runv [@bibcreator, @base.escape, quiet].compact.join(" ")
      run(num)
    end
  end

  def make_runcmd
    [@cmd, texname.escape, quiet].compact.join(" ")
  end

  # runs latex the specified number of times, renaming log files as it goes.
  def run(num=1)
    runcmd = make_runcmd
    num.times do 
      runv runcmd
      rename logname, logname + @cnt.to_s
      @cnt += 1
    end
  end

  def runv(*args)
    putsv "running: #{args.join(' ')}"
    system *args unless @dry
  end

  def delete_auxs(exts=AUX_EXTS)
    exts.each do |ext| 
      [nil,0,1,2].each do |n|
        unless @dry
          unlink @base.+("#{ext}#{n}")
        end
      end
    end
  end
end

opt = OpenStruct.new(biber: true, count: 2)

parser = OptionParser.new do |op|
  op.banner = "usage: #{File.basename(__FILE__)} [OPTS] <file>.tex"
  op.separator "output: <file>.pdf"
  op.separator ""
  op.separator "runs xelatex 'count' times"
  op.separator "if bibtex file exists, processes it, then reruns xelatex 'count' times"
  op.separator ""
  op.separator "note: "
  op.separator "  * removes <file>.pdf before running"
  op.separator "  * removes auxiliary files: <file>.{#{LatexRunner::AUX_EXTS.join(',')}}"
  op.separator ""
  op.separator "note: stalls if there are errors -- check <file>.log or .log{1-3}"
  op.separator ""
  op.separator "opts:"
  op.on("--latex-verbose", "spit out latex messages") {|v| opt.latex_verbose = v }
  op.on("--no-delete-pdf", "don't delete the pdf file before") {|v| opt.no_delete_pdf = v }
  op.on("-v", "--verbose", "what is happening") {|v| opt.verbose = v }
  op.on("--dirty", "leave auxiliary files") {|v| opt.dirty = v }
  op.on("--delete", "just delete auxiliary files") {|v| opt.delete = v }
  op.on("--dry", "don't run anything (verbose)") {|v| opt.dry = v && opt.verbose = v }
  op.on("--bibtex", "use bibtex instead of biber") {|v| opt.biber = false }
  op.on("--env", "print env variable export line and exit") {|v| opt.env = v }
  op.on("-c", "--count <#{opt.count}>", Integer, "run xelatex n times") {|v| opt.count = v }
end
parser.parse!

if opt.env
  puts ENV_VARS.map {|k,v| "export #{k}=#{v}" }.join("; ")
  exit
end

if ARGV.size == 0
  puts parser
  exit
end

bibcreator = opt.biber ? "biber" : "bibtex"
texfile = ARGV.shift

LatexRunner.new(
  texfile, 
  suppress_output: !opt.latex_verbose, 
  dry: opt.dry, 
  verbose: opt.verbose, 
  bibcreator: bibcreator
) do |lrunner|

  lrunner.delete_auxs

  exit if opt.delete

  lrunner.delete_pdf unless opt.no_delete_pdf

  lrunner.process(opt.count)

  lrunner.delete_auxs unless opt.dirty
end
