#!/usr/bin/env ruby



class NumericArray < Array
  # returns (new_x_coords, new_y_coords) of the same type as self
  # Where:
  #   self = the current x coordinates
  #   yvec = the parallel y coords 
  #   start = the initial x point
  #   endp = the final point
  #   increment = the x coordinate increment
  #   baseline = the default value if no values lie in a bin
  #   behavior = response when multiple values fall to the same bin
  #     sum => sums all values
  #     avg => avgs the values
  #     high => takes the value at the highest x coordinate
  #     max => takes the value of the highest y value [need to finalize]
  #     maxb => ?? [need to finalize]
  def inc_x(yvec, start=0, endp=2047, increment=1.0, baseline=0.0, behavior="sum")
    xvec = self

    scale_factor = 1.0/increment
    end_scaled = ((endp * (scale_factor)) + 0.5).to_int 
    start_scaled = ((start* (scale_factor)) + 0.5).to_int 

    # the size of the yvec will be: [start_scaled..end_scaled] = end_scaled - start_scaled + 1
    ## the x values of the incremented vector: 
    xvec_new_size = (end_scaled - start_scaled + 1)
    xvec_new = self.class.new(xvec_new_size)
    # We can't just use the start and endp that are given, because we might
    # have needed to do some rounding on them
    end_unscaled = end_scaled / scale_factor
    start_unscaled = start_scaled / scale_factor
    xval_new = start_unscaled
    xvec_new_size.times do |i|
      xvec_new[i] = start_unscaled
      start_unscaled += increment
    end

    # special case: no data
    if xvec.size == 0
      yvec_new = self.class.new(xvec_new.size, baseline)
      return [xvec_new, yvec_new]
    end

    ## SCALE the mz_scaled vector
    xvec_scaled = xvec.collect do |val|
      (val * scale_factor).round
    end

    ## FIND greatest index
    _max = xvec_scaled.last

    ## DETERMINE maximum value
    max_ind = end_scaled
    if _max > end_scaled; max_ind = _max ## this is because we'll need the room
    else; max_ind = end_scaled
    end

    ## CREATE array to hold mapped values and write in the baseline
    arr = self.class.new(max_ind+1, baseline)
    nobl = self.class.new(max_ind+1, 0)

    case behavior
    when "sum"
      xvec_scaled.each_with_index do |ind,i|
        val = yvec[i]
        arr[ind] = nobl[ind] + val
        nobl[ind] += val
      end
    when "high"  ## FASTEST BEHAVIOR
      xvec_scaled.each_with_index do |ind,i|
        arr[ind] = yvec[i]
      end
    when "avg"
      count = Hash.new {|s,key| s[key] = 0 }
      xvec_scaled.each_with_index do |ind,i|
        val = yvec[i]
        arr[ind] = nobl[ind] + val
        nobl[ind] += val
        count[ind] += 1
      end
      count.each do |k,co|
        if co > 1;  arr[k] /= co end
      end
    when "max" # @TODO: finalize behavior of max and maxb
      xvec_scaled.each_with_index do |ind,i|
        val = yvec[i]
        if val > nobl[ind];  arr[ind] = val; nobl[ind] = val end
      end
    when "maxb"
      xvec_scaled.each_with_index do |ind,i|
        val = yvec[i]
        if val > arr[ind];  arr[ind] = val end
      end
    else 
      warn "Not a valid behavior: #{behavior}, in one_dim\n"
    end

    trimmed = arr[start_scaled..end_scaled]
    if xvec_new.size != trimmed.size
      abort "xvec_new.size(#{xvec_new.size}) != trimmed.size(#{trimmed.size})"
    end
    [xvec_new, trimmed]
  end

  def /(other)
    nw = self.class.new
    if other.kind_of?(NumericArray)
      self.each_with_index do |val,i|
        nw << val / other[i]
      end
    else
      self.each do |val|
        nw << val / other
      end 
    end
    nw
  end

  def **(other)
    nw = self.class.new
    if other.kind_of?(NumericArray)
      self.each_with_index do |val,i|
        nw << (val ** other[i])
      end
    else
      self.each do |val|
        nw << val ** other
      end 
    end
    nw
  end

  def *(other)
    nw = self.class.new
    if other.kind_of?(NumericArray)
      self.each_with_index do |val,i|
        nw << val * other[i]
      end
    else
      self.each do |val|
        nw << val * other
      end 
    end
    nw
  end

  def +(other)
    nw = self.class.new
    if other.kind_of?(NumericArray)
      self.each_with_index do |val,i|
        nw << val + other[i]
      end
    else
      self.each do |val|
        nw << val + other
      end 
    end
    nw
  end

  def -(other)
    nw = self.class.new
    if other.kind_of?(NumericArray)
      self.each_with_index do |val,i|
        nw << val - other[i]
      end
    else
      self.each do |val|
        nw << val - other
      end 
    end
    nw
  end
end

require 'optparse'
require 'ostruct'
require 'mspire/mzml'

opt = OpenStruct.new( inc: 1.0, behavior: 'sum', baseline: 0.0)
parser = OptionParser.new do |op|
  op.banner = "usage: #{File.basename($0)} <file>.mzML"
  op.separator "output: <file>.lmata"
  op.on("-i", "--inc <#{opt.inc}>", Float, "increment to use") {|v| opt.inc = v }
  op.on("--start <Float>", Float, "will use scan window if present, otherwise supply") {|v| opt.start = v }
  op.on("--stop <Float>", Float, "will use scan window if present, otherwise supply") {|v| opt.stop = v }
  op.on("--bin-behavior <String>", "when more than one value lies in a bin", "sum|high|avg|max|maxb default: #{opt.behavior}") {|v| opt.behavior = v }
  op.on("--baseline <#{opt.baseline}>", Float, "baseline for missing data") {|v| opt.baseline = v }
end
parser.parse!

if ARGV.size == 0
  puts parser
  exit
end

ARGV.each do |file|
  spectra = []
  rts = []
  new_x = nil
  Mspire::Mzml.foreach(file) do |spectrum|
    if spectrum.ms_level == 1
      unless opt.start && opt.stop
        scan_window = spectrum.scan_list.first.scan_windows.first
        (opt.start, opt.stop) = %w(MS:1000501 MS:1000500).map {|acc| scan_window.fetch_by_acc(acc) }.map(&:to_f)
      end
      rts << spectrum.retention_time
      (new_x, new_y) = NumericArray.new(spectrum.mzs).inc_x(
        NumericArray.new(spectrum.intensities),
        opt.start,
        opt.stop,
        opt.inc,
        opt.baseline,
        opt.behavior
      )
      spectra << new_y
    end
  end

  base = file.chomp(File.extname(file))
  outfile = base + ".lmata"
  File.open(outfile, 'w') do |out|
    out.puts rts.size
    out.puts rts.join(" ")
    out.puts new_x.join(" ")
    spectra.each do |spectrum|
      out.puts spectrum.join(" ")
    end
  end
end


