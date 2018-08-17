#!/bin/bash

DAY=$1
TRACE_NO=$2

MIN_DAY=0
MAX_DAY=92

MIN_TRACE=1
MAX_TRACE=11

if [[ ($DAY -lt $MIN_DAY) || ($DAY -gt $MAX_DAY) ]]; then
	echo "Day has to be in ["$MIN_DAY", "$MAX_DAY"]"
	exit -1
fi

if [[ ($TRACE_NO -lt $MIN_TRACE) || ($TRACE_NO -gt $MAX_TRACE) ]]; then
	echo "Trace numbers can be in ["$MIN_TRACE", "$MAX_TRACE"], depending on the day"
	exit -1
fi

INPUT_TRACE="input/wc_day"$DAY"_"$TRACE_NO".gz"
echo "Input file: "$INPUT_TRACE

if [[ ! -f $INPUT_TRACE ]]; then
	echo "Trace "$INPUT_TRACE" does not exist."
	echo "Please provide the right combination of day and trace number."
	exit -1
fi

OUTPUT_FILE="output1_raw/unix_ts_"$DAY"_"$TRACE_NO".out"
echo "Output file: "$OUTPUT_FILE

gzip -dc $INPUT_TRACE | bin/recreate state/object_mappings.sort > $OUTPUT_FILE
