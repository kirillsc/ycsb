#!/bin/bash
mkdir output3_postprocessed/ -p

echo "" > jobs
for file in ./output2_raw_merged/*
do
	echo "./visuallize_world_cup.py --src_file $file --out_folder ./output3_postprocessed" >> jobs
done

cat jobs | parallel -u --joblog results.log


