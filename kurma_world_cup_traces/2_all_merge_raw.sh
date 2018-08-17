#!/bin/bash
mkdir output2_raw_merged/ -p

for day in {0..100..1}
do
	rm ./output2_raw_merged/day_$day.out -f
	for  f in ./output1_raw/unix_ts_"$day"_*
	do
		echo $f
		cat $f >> ./output2_raw_merged/day_$day.out
#		./run_single.sh $day $trace
	done
	echo "----------_"
done

