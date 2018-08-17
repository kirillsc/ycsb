#!/bin/bash
mkdir output4_plots/ -p

for file in ./output3_postprocessed/*
do
	file="$(basename $file)"
	echo "IN  FILE: "$file

	gnuplot -e "infile='$file'" ./plot.plot
	#gnuplot -e \"infile='$((file))'\" -e \"outfile='$((file)).pdf'\" ./plot.plot
done


