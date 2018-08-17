#!/bin/bash

REPO=ftp://ita.ee.lbl.gov/traces/WorldCup
TRACE_PREFIX=wc_day
TRACE_SUFFIX=gz
TOTAL_DAYS=92
MAX_TRACES_PER_DAY=11
# These traces will become inputs to our processing code
OUTPUT_DIR=input/

for (( i=1; i<=$TOTAL_DAYS; i++ ))
do
	# Some days do not have any intervals, so some of the wgets will fail
	for (( j=1; j<=$MAX_TRACES_PER_DAY; j++ ))
	do
		wget -P $OUTPUT_DIR $REPO/${TRACE_PREFIX}${i}_${j}.$TRACE_SUFFIX
		# Once a wget fails, do not attempt to fetch any subsequent subtraces
		# as there are no any! Move to the next day..
		if [[ $? != 0 ]]; then
			subtraces=$((j - 1))
			echo "Day "$i" has only "$subtraces" subtraces"
			break;
		fi
		# Example ftp://ita.ee.lbl.gov/traces/WorldCup/wc_day1_1.gz
	done
done
