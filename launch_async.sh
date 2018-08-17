#!/bin/bash
THREADS=64
OUT_FILE=out_1.ycsb
OUT_FILE_RAW=./raw_out/out.ycsb
OUT_TRACE_ONLY=trace.cat
TRACE=./synthetic_trace_6000_100_poisson.data_scle_1_ycsb.trace

#export _JAVA_OPTIONS="-XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintHeapAtGC -XX:+PrintTenuringDistribution -XX:+PrintGCApplicationStoppedTime -XX:+PrintPromotionFailure -Xloggc:/home/kirillb/projects/lx3/sources/nc_ycsb/gc.ycsb.log -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=10M"

DEFAULTS="run cassandra-cql -P workloads/workloadc -s -p port=9042 -p cassandra_writeconsistencylevel=ONE -cp ./slf4j-simple-1.7.12.jar:./../tec_javadriver/driver-core/target/cassandra-driver-core-3.0.8-SNAPSHOT.jar -p driver_maxqueuesize=100000 -p driver_newconnection_threshold_local=1024 -p driver_maxrequests_perconnection_local=2048 -p measurement.interval=both -p recordcount=100000"


./bin/ycsb run cassandra-cql -P workloads/workloadc -s \
        -threads $THREADS -p hosts=192.168.102.1 \
        -p cassandra.readconsistencylevel=ONE \
        -p measurement.interval=both \
        -cp ./slf4j-simple-1.7.12.jar:./../tec_javadriver/driver-core/target/cassandra-driver-core-3.0.8-SNAPSHOT.jar \
        \
        -p tracefile=$TRACE \
        -p workload=com.yahoo.ycsb.workloads.TraceWorkload \
        -p sendasync=true \
        -p print_dispatching_timestamps=true \
        -p measurementtype=rawoptimized \
        -p measurement.raw.output_file=$OUT_FILE_RAW \
        -p measurement.raw.temp_file=./raw_tmp/ \
        -p warmupperiod=60 \
        \
        -p driver_loadbalancer=roundrobin > $OUT_FILE



echo "|||| Plotting results ||||"
cat $OUT_FILE_RAW | grep " R " > $OUT_TRACE_ONLY

visualize_ycsb_trace.R --intended_ts_file $TRACE --actual_ts_file $OUT_TRACE_ONLY --duration 10000 --interval 1

