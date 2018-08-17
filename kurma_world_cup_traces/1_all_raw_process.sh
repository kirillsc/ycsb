#!/bin/bash
mkdir output1_raw/ -p

for day in `seq 0 100`
do
	for  index in {1..11..1}
	do
		echo $day $index
		./run_single.sh $day $index
	done
done

