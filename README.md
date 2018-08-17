<!--
Copyright (c) 2010 Yahoo! Inc., 2012 - 2016 YCSB contributors.
All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License"); you
may not use this file except in compliance with the License. You
may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
implied. See the License for the specific language governing
permissions and limitations under the License. See accompanying
LICENSE file.
-->

KURMA Dynamic (YCSB)
====================================

This repository contains a modified version of popular Yahoo! Cloud System Benchmark (YCSB). In this version, YCSB can generate trace-driven workloads by adhering to the request generation rates specified by input trace files. Moreover, we allow YCSB to use an asynchronous query mechanism so that it behaves simlarly to an Open Loop generator. This can allow us to sustain high rates of request generation without requiring a large number of threads. Additionally, it can make workload generation more deterministic since it circumvents the "back-off" mechanism inherent to Closed Loop Generators. This property can be useful for result reproducibility and for configurations where client-side queuing is undesirable (even when the system is stressed). Lastly, we modified the way YCSB measures request completion time, such that the overhead of such measurements is significantly reduced (improving accuracy).


Authors: Waleed Reda [wfhsr@kth.se] Kirill L. Bogdanov [kirillb@kth.se]

###1.Workload Trace Format

Each YCSB trace file is a simple one column text file where each row represents a request. The while in each row indicates the time (from the moment when YCSB sends first request) in nanoseconds when this request needs to be generated and sent out. By following this simple format you can generate traces with any distributions. Trace file is read once at the beginning of the benchmark, while all timestamps are stored in memory.

**Example trace file:**
```sh
0
148000
311000
480000
665000
841000
1016000
1179000
1354000
1496000
```


###2.YCSB Output

TraceWorkload class was designed to collect raw results - namely, the sending and completion times of requests - while running YCSB. The formats of the possible output measurements can be found below:


  - **`READ,1534404005505,69857`** : YCSB default output. Indicates the type of the operation, the **actual** time the operation was sent (in ns), and the corresponding request completion time in us.
  
  - **`Intended-READ,1534404102472,435`** : YCSB's intended latencies. Indicates the type of the operation, the **intended** time the operation should have been sent (in ns), and the corresponding request completion time in us. To display this measurement, set the **measurement.interval** argument to `both`.

  - **`1 R 99917000000`** : Relative timestamp in nanoseconds of when request was sent. Should be the same as **Intended** send time (but does not measure the correspondinng completion times). To display this measurement, set the **print_dispatching_timestamps** argument to `True`.


Note 1: **Intended** measurements can deviate from the **actual** latency measurement if request generation was delayed due [Coordinated Omission](https://medium.com/@siddontang/the-coordinated-omission-problem-in-the-benchmark-tools-5d9abef79279). If it is desirable to issue requests more determinstically, set YCSB's **sendasync** option to `True` as specified in Section 3.

Note 2: While vanilla YCSB also has functionality to record request completion times for every generated request, we found that using this option as-is significantly affects observed results. Specifically, at high loads YCSB client introduces significant delays while recording and storing timestamps for every request. Thus, we introduced `rawoptimized` measurement method that alleviates some of these delays by using more efficient serialization methods.

###3.Dynamic YCSB command line arguments


  - **-p workload=com.yahoo.ycsb.workloads.TraceWorkload** Sets the workload generator to trace-mode. In this setting, YCSB relies on a (pre-defined) trace file's timestamps to decide when to send requests. By default, this option is disabled.
  - **-p starttime=1527978460711** Sets the start time for all Kurma instances (used for synchronization purposes). Inputted in milliseconds as a Long (following the format of System.currentTimeMillis).
  - **-p print_dispatching_timestamps=** `["True", "False"]` If set to true, will print " R " lines in the .ycsb file to later plot intended and actual request sent times. By default false.
  - **-p sendasync=** `["True", "False"]`  If set to true, configures Cassandra CQL client to send requests asynchronously without blocking threads until response is received/timed-out (this feature is currently only implemented for read requests).
  - **-p warmupperiod=60** Sets the warm up period for YCSB (in seconds), important for open loop request generation as high spike of requests on a "cold" server might create a cascading effect such that server (Cassandra) never recovers from the overwhelming stream of requests. Note that this only works for the TraceWorkoad. We set the sending rate during the warmup period to be equivalent to the rate of the 1st minute from the provided trace. Otherwise, set according to the default target parameter.
  - **-p warmupperiod_intervals=5** Divides warmup period into increasing function with N (here=5) steps. For example, if the first minute of the trace has 1000 req/s on average, warmupperiod=60 and warmupperiod_intervals=5 then YCSB will start by generating (1000 / 5) 200 req/s for (60 / 5) 12 seconds, Then 400 req/s for the next 12 sec of the trace etc. After 60 seconds, normal trace replay will begin.
  - **-p measurement.interval=** `["op", "both"]` Configures YCSB to output both the actual and the intended latencies. Intended latencies are calculated based on when a request SHOULD have been sent. They are relevant when YCSB fails to send requests at the specified target or trace timestamps.
  - **-p measurementtype=rawoptimized** New measurement type.
  - **-p measurement.raw.output_file=./output.ycsb**
  - **-p measurement.raw.temp_file=/mnt/ram/** If output results aren't being written to stdout. This is done to avoid contention between threads, so each thread gets to write to its own file directly. To further reduce delays it is recommended to have this folder mounted to a RAM disk. After trace has been replayed, YCSB's TraceWorkload class will go through all files in this folder and merge them into a single file.
  - **-p tracefile="custom_workloads/samples/trace1"** Sets the relative path to the trace file.
  - **-p spin.sleep=** `["True", "False"]` Configures the thread to busy-wait (and not sleep) when throttling is in effect. Throttling can occur if the sending rate has exceeded a specified target or if YCSB is operating in trace-mode. By default sleep is set to false.
  - **-p driver_maxqueuesize=** Set to a large number (say 20k+) for open loop trace replays. If YCSB uses a lot of threads then some queuing can occur (especially at the start of the test).
  - **-p measurement_raw_format=** `["binary"]` If set to binary, the raw measurements class will write the data points in binary to a separate file "out.bycsb". By default, the data is written as text.
  - **-p driver_retry=** Sets the retry policy for the driver. Set to 'none' to disable retries.


###4.Example of running YCSB

```sh
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

```


Note, the modified version of YCSB was tested only with Cassandra 3.0.


###Generating YCSB workload traces from WorldCup98 traces

This repository also contains **kurma_world_cup_traces** folder which has scripts to convert WorldCup98 traces into YCSB format. Navigate into this folder and follow instructions in the README.md. Once WorldCup98 traces are pre-formatted, use scripts from the following section to convert them into YCSB compatible format.


###Generating arbitrary YCSB workload traces


**kurma_workload_traces** contains scripts to generate simple synthetic workloads based on Poisson interarrival time. Navigate into this folder and follow instructions in the README.md



Yahoo! Cloud System Benchmark (YCSB)
====================================
[![Build Status](https://travis-ci.org/brianfrankcooper/YCSB.png?branch=master)](https://travis-ci.org/brianfrankcooper/YCSB)

Links
-----
http://wiki.github.com/brianfrankcooper/YCSB/
https://labs.yahoo.com/news/yahoo-cloud-serving-benchmark/
ycsb-users@yahoogroups.com

Getting Started
---------------

1. Download the [latest release of YCSB](https://github.com/brianfrankcooper/YCSB/releases/latest):

    ```sh
    curl -O --location https://github.com/brianfrankcooper/YCSB/releases/download/0.12.0/ycsb-0.12.0.tar.gz
    tar xfvz ycsb-0.12.0.tar.gz
    cd ycsb-0.12.0
    ```

2. Set up a database to benchmark. There is a README file under each binding
   directory.

3. Run YCSB command.

    On Linux:
    ```sh
    bin/ycsb.sh load basic -P workloads/workloada
    bin/ycsb.sh run basic -P workloads/workloada
    ```

    On Windows:
    ```bat
    bin/ycsb.bat load basic -P workloads\workloada
    bin/ycsb.bat run basic -P workloads\workloada
    ```

  Running the `ycsb` command without any argument will print the usage.

  See https://github.com/brianfrankcooper/YCSB/wiki/Running-a-Workload
  for a detailed documentation on how to run a workload.

  See https://github.com/brianfrankcooper/YCSB/wiki/Core-Properties for
  the list of available workload properties.

Building from source
--------------------

YCSB requires the use of Maven 3; if you use Maven 2, you may see [errors
such as these](https://github.com/brianfrankcooper/YCSB/issues/406).

To build the full distribution, with all database bindings:

    mvn clean package

To build a single database binding:

    mvn -pl com.yahoo.ycsb:mongodb-binding -am clean package
