#!/usr/bin/gnuplot
set grid ytics lc rgb "#444444" lw 1 lt 1 dt 3
set grid xtics lc rgb "#444444" lw 1 lt 1 dt 3


darkblue="#3366cc"
darkred="#dc3912"
darkyellow="#ff9900"
lightyellow="#ffcc77"
middleyellow="#ffbb55"
darkgreen="#109618"
darkpurple="#990099"
darkcyan="#0099c6"
black="#000000"
gray="#777777"
lightgray="#cccccc"
white="#ffffff"


if (!exists("COMMON_LINE_WIDTH")) COMMON_LINE_WIDTH=1

set style line 1  lw COMMON_LINE_WIDTH lt rgb(darkblue)
set style line 2  lw COMMON_LINE_WIDTH lt rgb(darkred)
set style line 3  lw COMMON_LINE_WIDTH lt rgb(darkgreen)
set style line 4  lw COMMON_LINE_WIDTH lt rgb(darkyellow)
set style line 5  lw COMMON_LINE_WIDTH lt rgb(darkpurple)
set style line 6  lw COMMON_LINE_WIDTH lt rgb(darkcyan)
set style line 7  lw COMMON_LINE_WIDTH lt rgb(black)
set style line 8  lw COMMON_LINE_WIDTH lt rgb(gray)
set style line 9  lw COMMON_LINE_WIDTH lt rgb(lightgray)
set style line 50 lw COMMON_LINE_WIDTH lt rgb(white)
set style increment user

LS_WHITE_LINE=50

lower="no wait"
barriers="barriers (baseline)"
adaptive_200="adaptive 200"
adaptive_250="adaptive 250"
timeout="timeout"
sequential="sequential"
general="general"


fskip_over(x, max) = x > max ? NaN : x

fskip_under(x, min) = x < min ? NaN : x



## Special Symbols for micro seconds etc
# μ

