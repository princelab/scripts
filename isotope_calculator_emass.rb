#!/usr/bin/env ruby

=begin
The MIT License (MIT)

Copyright (c) 2014 Brigham Young University
Authored by John T. Prince with Bradley Naylor assisting (July 14, 2014)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
=end

require 'optparse'
require 'open3'
require 'ostruct'

# masses and ratios are parallel arrays
IsotopeDist = Struct.new(:formula, :charge, :limit, :masses, :ratios, :deuterium_pct)

# returns an IsotopeDist object
def read_emass_output(output, deuterium_pct=0.0)
  lines = output.split(/\r?\n/)
  header = lines.shift
  (formula, charge, limit) = header.match(/formula: ([\w\d]+) charge : ([\d\+\-]+) limit: ([\w\d\.e\+\-]+)/).captures
  masses = []
  ratios = []
  lines.each do |line| 
    (m,r) = line.split(' ')
    masses << m.to_f
    ratios << r.to_f
  end
  IsotopeDist.new(formula, charge, limit, masses, ratios, deuterium_pct)
end

def get_isotope_array
  DATA.readlines.map {|line| line.chomp << "\r\n" }
end

isotope_array = get_isotope_array
HYDROGEN_START_INDEX = isotope_array.index {|line| line[0] == 'H' }
DEUTERIUM_FRACTION = isotope_array[6].chomp.split(' ').last.to_f

# returns the hydrogen fraction and deuterium fraction given a deuterium
# percentage
def calculate_deuterium_fractions(deuterium_pct)
  new_deut_frac = (deuterium_pct + (100.0 - deuterium_pct) * DEUTERIUM_FRACTION) / 100
  new_hydrogen_frac = 1.0 - new_deut_frac
  [new_hydrogen_frac, new_deut_frac]
end

def write_isotope_array(isotope_array, deuterium_pct, io)
  new_array = isotope_array.dup
  (hydr, deut) = calculate_deuterium_fractions(deuterium_pct)
  [1,2].zip([hydr, deut]) do |i, fraction|
    mass_num_st = isotope_array[HYDROGEN_START_INDEX+i].split(" ").first 
    new_array[HYDROGEN_START_INDEX+i] = "#{mass_num_st} #{fraction}\r\n"
  end
  io.write(new_array.join)
end

def normalize(ratios)
  sum = ratios.reduce(:+)
  ratios.map {|v| v / sum }
end

opt = OpenStruct.new( start: 0.0, stop: 5.0, step: 0.2 )

parser = OptionParser.new do |op|
  op.banner = "usage: #{File.basename(__FILE__)} <MolFormula> ..."
  op.separator "output: csv header line, then masses and ratios, one per line"
  op.separator ""
  op.separator "notes:"
  op.separator "uses Neese isotope ratios [biological] on top of default ratios from emass"
  op.separator "requires 'emass' to be callable from PATH"
  op.separator "get emass from: http://www.helsinki.fi/science/lipids/software.html"
  op.separator ""
  op.separator "options:"
  op.on("-o", "--outfile <fname>", "write to outfile") {|v| opt.outfile = v }
  op.on("-i", "--infile <fname>", "use an input file, one formula per line") {|v| opt.infile = v }
  op.on("-n", "--normalize", "normalize ratios to one") {|v| opt.normalize = v }
  op.on("--start <#{opt.start}>", Float, "deuterium start") {|v| opt.start = v }
  op.on("--stop <#{opt.stop}>", Float, "deuterium stop") {|v| opt.stop = v }
  op.on("--step <#{opt.step}>", Float, "deuterium step") {|v| opt.step = v }
end
parser.parse!

if ARGV.size == 0 && opt.infile.nil?
  puts parser
  exit
end

mol_forms = 
  if opt.infile
    IO.readlines(opt.infile).reject {|line| line !~ /\w/}.map(&:chomp)
  else
    ARGV.dup
  end

  
out = opt.outfile ? File.open(opt.outfile, 'w') : $stdout
puts "writing to: #{opt.outfile}"

mol_forms.each do |mol_form|
  (opt.start..opt.stop).step(opt.step) do |deuterium_pct|
    file = mol_form + "Dpct_#{deuterium_pct}" + ".isotope_ratios.tmp"
    File.open(file, 'w') {|io| write_isotope_array(isotope_array, deuterium_pct, io) }
    isotope_output = nil
    Open3.popen3("emass -i #{file}") do |stdin, stdout, stderr, wait_thr|
      stdin.write("#{mol_form}\n")
      stdin.close_write
      isotope_output = stdout.read
    end
    isotope_dist = read_emass_output(isotope_output, deuterium_pct)
    File.unlink(file)
      out.puts [:formula, :charge, :limit, :deuterium_pct].flat_map {|v| ["#{v}:", isotope_dist.send(v)] }.join(", ")
      
      ratios = opt.normalize ? normalize(isotope_dist.ratios) : isotope_dist.ratios
      isotope_dist.masses.zip(ratios) do |pair|
        out.puts pair.join(", ")
      end
    end
end
out.close if opt.outfile

## these are from ISOTOPE.DAT (originally from emass code) but altered to have
# the neese ratios (see mspire library).
# the original file uses \r\n, but this is \n
__END__
X  2
1  0.9
2  0.1

H  2
1.0078246  0.999844
2.0141021  0.000156

He  2
3.01603    0.00000138
4.00260    0.99999862

Li  2
6.015121   0.075
7.016003   0.925

Be  1
9.012182   1.0

B  2
10.012937  0.199
11.009305  0.801

C  2
12.0000000 0.9891
13.0033554 0.0109

N  2
14.0030732 0.99635
15.0001088 0.00365

O  3
15.9949141 0.99759
16.9991322 0.00037
17.9991616 0.00204

F  1
18.9984032 1.0

Ne  3
19.992435  0.9048
20.993843  0.0027
21.991383  0.0925

Na  1
22.989767  1.0

Mg  3
23.985042  0.7899
24.985837  0.1000
25.982593  0.1101

Al  1
26.981539  1.0

Si  3
27.976927  0.9223
28.976495  0.0467
29.973770  0.0310

P  1
30.973762  1.0

S  4
31.972070  0.9493
32.971456  0.0076
33.967866  0.0429
35.967080  0.0002

Cl  2
34.9688531 0.755290
36.9659034 0.244710

Ar  3
35.967545  0.00337
37.962732  0.00063
39.962384  0.99600

K  3
38.963707  0.932581
39.963999  0.000117
40.961825  0.067302

Ca  6
39.962591  0.96941
41.958618  0.00647
42.958766  0.00135
43.955480  0.02086
45.953689  0.00004
47.952533  0.00187

Sc  1
44.955910  1.0

Ti  5
45.952629  0.080
46.951764  0.073
47.947947  0.738
48.947871  0.055
49.944792  0.054

V  2
49.947161  0.00250
50.943962  0.99750

Cr  4
49.946046  0.04345
51.940509  0.83790
52.940651  0.09500
53.938882  0.02365

Mn  1
54.938047  1.0

Fe  4
53.939612  0.0590
55.934939  0.9172
56.935396  0.0210
57.933277  0.0028

Co  1
58.933198  1.0

Ni  5
57.935346  0.6827
59.930788  0.2610
60.931058  0.0113
61.928346  0.0359
63.927968  0.0091

Cu  2
62.939598  0.6917
64.927793  0.3083

Zn  5
63.929145  0.486
65.926034  0.279
66.927129  0.041
67.924846  0.188
69.925325  0.006

Ga  2
68.925580  0.60108
70.924700  0.39892

Ge  5
69.924250  0.205
71.922079  0.274
72.923463  0.078
73.921177  0.365
75.921401  0.078

As  1
74.921594  1.0

Se  6
73.922475  0.009
75.919212  0.091
76.919912  0.076
77.9190    0.236
79.916520  0.499
81.916698  0.089

Br  2
78.918336  0.5069
80.916289  0.4931

Kr  6
77.914     0.0035
79.916380  0.0225
81.913482  0.116
82.914135  0.115
83.911507  0.570
85.910616  0.173

Rb  2
84.911794  0.7217
86.909187  0.2783

Sr  4
83.913430  0.0056
85.909267  0.0986
86.908884  0.0700
87.905619  0.8258

Y  1
88.905849  1.0

Zr  5
89.904703  0.5145
90.905644  0.1122
91.905039  0.1715
93.906314  0.1738
95.908275  0.0280

Nb  1
92.906377  1.0

Mo  7
91.906808  0.1484
93.905085  0.0925
94.905840  0.1592
95.904678  0.1668
96.906020  0.0955
97.905406  0.2413
99.907477  0.0963

Tc  1
98.0   1.0

Ru  7
95.907599  0.0554
97.905287  0.0186
98.905939  0.127
99.904219  0.126
100.905582  0.171
101.904348  0.316
103.905424  0.186

Rh  1
102.905500  1.0

Pd  6
101.905634  0.0102
103.904029  0.1114
104.905079  0.2233
105.903478  0.2733
107.903895  0.2646
109.905167  0.1172

Ag  2
106.905092  0.51839
108.904757  0.48161

Cd  8
105.906461  0.0125
107.904176  0.0089
109.903005  0.1249
110.904182  0.1280
111.902758  0.2413
112.904400  0.1222
113.903357  0.2873
115.904754  0.0749

In  2
112.904061  0.043
114.903880  0.957

Sn  10
111.904826  0.0097
113.902784  0.0065
114.903348  0.0036
115.901747  0.1453
116.902956  0.0768
117.901609  0.2422
118.903310  0.0858
119.902200  0.3259
121.903440  0.0463
123.905274  0.0579

Sb  2
120.903821  0.574
122.904216  0.426

Te  8
119.904048  0.00095
121.903054  0.0259
122.904271  0.00905
123.902823  0.0479
124.904433  0.0712
125.903314  0.1893
127.904463  0.3170
129.906229  0.3387

I  1
126.904473  1.0

Xe  9
123.905894  0.0010
125.904281  0.0009
127.903531  0.0191
128.904780  0.264
129.903509  0.041
130.905072  0.212
131.904144  0.269
133.905395  0.104
135.907214  0.089

Cs  1
132.905429  1.0

Ba  7
129.906282  0.00106
131.905042  0.00101
133.904486  0.0242
134.905665  0.06593
135.904553  0.0785
136.905812  0.1123
137.905232  0.7170

La  2
137.90711   0.00090
138.906347  0.99910

Ce  4
135.907140  0.0019
137.905985  0.0025
139.905433  0.8843
141.909241  0.1113

Pr  1
140.907647  1.0

Nd  7
141.907719  0.2713
142.909810  0.1218
143.910083  0.2380
144.912570  0.0830
145.913113  0.1719
147.916889  0.0576
149.920887  0.0564

Pm  1
145.0  1.0

Sm  7
143.911998  0.031
146.914895  0.150
147.914820  0.113
148.917181  0.138
149.917273  0.074
151.919729  0.267
153.922206  0.227

Eu  2
150.919847  0.478
152.921225  0.522

Gd  7
151.919786  0.0020
153.920861  0.0218
154.922618  0.1480
155.922118  0.2047
156.923956  0.1565
157.924099  0.2484
159.927049  0.2186

Tb  1
158.925342  1.0

Dy  7
155.925277  0.0006
157.924403  0.0010
159.925193  0.0234
160.926930  0.189
161.926795  0.255
162.928728  0.249
163.929171  0.282

Ho  1
164.930319  1.0

Er  6
161.928775  0.0014
163.929198  0.0161
165.930290  0.336
166.932046  0.2295
167.932368  0.268
169.935461  0.149

Tm  1
168.934212  1.0

Yb  7
167.933894  0.0013
169.934759  0.0305
170.936323  0.143
171.936378  0.219
172.938208  0.1612
173.938859  0.318
175.942564  0.127

Lu  2
174.940770  0.9741
175.942679  0.0259

Hf  6
173.940044  0.00162
175.941406  0.05206
176.943217  0.18606
177.943696  0.27297
178.945812  0.13629
179.946545  0.35100

Ta  2
179.947462  0.00012
180.947992  0.99988

W  5
179.946701  0.0012
181.948202  0.263
182.950220  0.1428
183.950928  0.307
185.954357  0.286

Re  2
184.952951  0.3740
186.955744  0.6260

Os  7
183.952488  0.0002
185.953830  0.0158
186.955741  0.016
187.955860  0.133
188.958137  0.161
189.958436  0.264
191.961467  0.410

Ir  2
190.960584  0.373
192.962917  0.627

Pt  6
189.959917  0.0001
191.961019  0.0079
193.962655  0.329
194.964766  0.338
195.964926  0.253
197.967869  0.072

Au  1
196.966543  1.0

Hg  7
195.965807  0.0015
197.966743  0.100
198.968254  0.169
199.968300  0.231
200.970277  0.132
201.970617  0.298
203.973467  0.0685

Tl  2
202.972320  0.29524
204.974401  0.70476

Pb  4
203.973020  0.014
205.974440  0.241
206.975872  0.221
207.976627  0.524

Bi  1
208.980374  1.0

Po  1
209.0  1.0

At  1
210.0  1.0

Rn  1
222.0  1.0

Fr  1
223.0  1.0

Ra  1
226.025  1.0

Ac  1
227.028  1.0

Th  1
232.038054  1.0

Pa  1
231.0359  1.0

U  3
234.040946  0.000055
235.043924  0.00720
238.050784  0.992745

Np  1
237.048  1.0

Pu  1
244.0  1.0

Am  1
243.0  1.0

Cm  1
247.0  1.0

Bk  1
247.0  1.0

Cf  1
251.0  1.0

Es  1
252.0  1.0

Fm  1
257.0  1.0

Md  1
258.0  1.0

No  1
259.0  1.0

Lr  1
260.0  1.0
