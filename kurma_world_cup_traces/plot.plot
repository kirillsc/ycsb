#!/usr/bin/gnuplot

set terminal png dl 1.5 enhanced  size 800,600 font "Helvetica,15"
# set terminal postscript monochrome




##-LABELS-################################################################################
set ylabel 'Rate' offset 2.5,0
set xlabel 'Time [min]' offset 0,1
set title "Rate of Arrival"

set key Left bottom inside samplen 2 vertical maxrows 6 reverse

COMMON_LINE_WIDTH=2
#load 'common.plot'
##-RANGES-################################################################################

# set xrange[0:0.5]
unset xrange
unset yrange
# set yrange[0.0:50]

#set mytics 2
#set mxtics 5
# set xtics 0.1


##-DATA-##################################################################################


f(x) = x / 1000.0 / 1000.0
f1(x) = x / 1000.0




outfile1="./output4_plots/1minRate_".infile.".png"

outfile2="./output4_plots/10secRate_".infile.".png"
outfile3="./output4_plots/1secRate_".infile.".png"
infile = "./output3_postprocessed/".infile


#print "infile    ".infile
#print "outfile   ".outfile

f(x) = x / 60.0
ff(x) = x # * 6

set output outfile1
plot \
	infile u (f($4)):8 every 50 w l  lt 1 title "1 min"

#set output outfile2
#plot \
#	infile u (f($4)):(ff($7)) every::::1000  w l lt 2 title "10 sec (times 6)"

# set output outfile3
# plot \
# 	infile u (f($4)):($6) every::::2000  w l lt 3 title "1 sec"
