#!/usr/bin/env ruby

require 'trollop'

def ppm_adjust(val, ppm)
  (val * (1e6 - ppm)) / 1e6
end

# sometimes has a leader string "mz".  This will remove that first and then
# cast to Float.
def ensure_numeric(string)
  Float( string.sub(/\Amz/,'') )
end

class LinearInterp
  attr_accessor :functions

  def initialize(functions)
    @functions = functions
  end

  def recal(val)
    f = @functions.find {|f| f === val }
    abort 'no function matched!' unless f
    f.recal(val)
  end

  def self.from_xy_bins(xy_bins)
    functions = xy_bins.each_cons(2).map do |pair_a, pair_b|
      m = (pair_b.last - pair_a.last) / (pair_b.first - pair_a.first)
      b = pair_b.last - (m*pair_b.first)
      Function.new(pair_a.first, pair_b.first, m, b)
    end
    LinearInterp.new(functions)
  end
end

class Function < Range
  attr_accessor :m
  attr_accessor :b

  def initialize(beg, endv, m, b)
    super(beg, endv)
    @m = m
    @b = b
  end

  def recal(val)
    ppm_dev = (m * val) + b
    ppm_adjust(val, ppm_dev)
  end
end


parser = Trollop::Parser.new do 
  banner "usage: #{File.basename(__FILE__)} [OPTIONS] quant_compare.tsv header_name"

  opt :ppm_recal, "vals deviate this amount", :default => 0.0
  opt :linear_interp, "begin,end,m,b[:...]", :type => String
  opt :interp_bins, "x,y:x,y...", :type => String

end

opts = parser.parse(ARGV)

if ARGV.size != 2
  parser.educate
  exit
end

(file, col_name) = ARGV

if opts[:linear_interp]
  functions = opts[:linear_interp].split(':').map do |str|
    Function.new( *str.split(',').map(&:to_f) )
  end
  opts[:linear_interp] = LinearInterp.new(functions)
end

if opts[:interp_bins]
  xy_pairs = opts[:interp_bins].split(':').map {|st| st.split(',').map(&:to_f) }
  opts[:linear_interp] = LinearInterp.from_xy_bins(xy_pairs)
end

lines = IO.readlines(file).map(&:chomp)
header_line = lines.shift

i = header_line.split("\t").index(col_name)

base = file.chomp(File.extname(file))
base = base + ".#{opts[:ppm_recal]}ppm" if opts[:ppm_recal]
base = base + ".linear_interp" if opts[:linear_interp]

outfile = base + ".ONLY_MZS.txt"

File.open(outfile,'w') do |out|
  lines.each do |line|
    data = line.chomp.split("\t")
    mz = ensure_numeric(data[i])
    if opts[:ppm_recal]
      mz = ppm_adjust(mz, opts[:ppm_recal])
    end
    
    if opts[:linear_interp]
      mz = opts[:linear_interp].recal(mz)
    end
   
    out.puts mz
  end
end
