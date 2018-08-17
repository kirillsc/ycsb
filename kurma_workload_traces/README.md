


#generate_synt_traces.sh

This script generates synthesized YCSB workload trace with constant Poisson distribution. Each trace file has two parameters (i) request arrival rate per second and (ii) duration (seconds). See script for details.



#create_ycsb_trace.R

In contrast to generate_synt_traces.sh, this script can take pre-processed WorldCup98 trace and generate a workload trace that can be fed into YCSB. The problem that this script solves, is that original WorldCup98 trace recorded at a second resolution. Thus, when more than one request arrives within one second, we do not know how these requests distributed within each second. This script distributes requests within each second of the trace according to a given distribution.

  * ''--vertical_scale'' or ''-vscale'' can be set to scaly arrival rate without modifying the length of the trace
  * ''--duration'' or ''-d'' can be set to specify the interval for binning the timestamps and generating requests using the specified inter-arrival distribution

Example Usage:

```bash
Rscript create_ycsb_trace.R --src_file "samples/unix_ts_10_1.out_reg1.data" --arrival_distr poisson --vertical_scale 2.0 --duration 1

output is 1 files:
samples/unix_ts_10_1.out_reg1.data_ycsb.data
```

This parses the specified trace file "samples/unix_ts_10_1.out_reg1.data" and generates additional timestamps based on the no. of requests arrived during each 1 sec interval. The arrival_distr parameter specifies that a "poisson" process is used to generate the interarrivals.

```bash
Rscript create_ycsb_trace.R --duration 3600 --rate 1000 --arrival_distr constant

output is 1 files:
samples/synthetic_trace_1000_3600_constant.data_ycsb.data
```

If no trace file is specified, the command will use the specified parameters to generate a synthetic trace. In this case, we generate a 1 hr trace file with an average rate of 1000 req/s. The arrival_distr parameter specifies a constant interarrival time.

Both commands produce an output in the following format:

```bash
relative_timestamp_ns
0
387456232000
422328388444
459873739972
838777321292
2000000000000
2392927477278
2485877374777
```

#scale_ycsb_trace.R

This script is an optional fourth stage of parsing, it takes traces produced by create_ycsb_trace.R and scales them up or down. In addition, the script can also repeat the trace successively as necessary.

Example:

```bash
Rscript scale_ycsb_trace.R --src_files samples/unix_ts_10_1.out_reg1.data_ycsb.data --scale_factor 0.01 --repetition 5

output is 1 files:
unix_ts_10_1.out_reg1.data_ycsb.data_scalefactor_0.01_repetition_5.data
```

#visualize_ycsb_trace.R

This script produces a line plot for a timeseries of requests sent during X seconds for both the intended and actual trace.

Example:

```bash
Rscript visualize_ycsb_trace.R --intended_ts_file samples/original_trace.data --actual_ts_file samples/ycsb_trace.data --duration 60 --interval 1
```

This command takes the original trace "samples/original_trace.data" and the actual trace produced by ycsb "ycsb_trace.data" to produce a line plot comparing the total requests sent by each. The graph produced covers a duration of 60 sec and the requests sent are counted at 1 sec intervals.

Note: If duration is not specified, the script defaults to using the minimum of both trace file durations.

#trace_analysis_script1.R
This script computes the scaling factor for a given set of traces and desired maximal capacity. Optionally, it can also output the raw data points of the scaled traces along with their timeseries.

Example:

```bash
Rscript trace_analysis_script1.R --src_dir /traces/day1 --dst_dir /traces/day1/scaled --interval 60 --capacities 0,15000,30000,45000,55000,60000 --vms 5 --enableRaw
```

This command will compute the scaling factor from the traces provided in "/traces/day1/". The scaling factor is performed based on the maximal average rates reported across 60 second intervals and the provided max cluster size. In this case, since the max number of 'vms' is 5, we will scale our traces up to a rate of 60000 reqs/s. It will then output the raw datapoints of the scaled traces (with .strace extensions) as well as their plotted timeseries to "/traces/day1/scaled/".

```bash
Rscript trace_analysis_script1.R --src_dir /traces/day1 --interval 60
```

This command will compute the scaling factor as reported previously. However, no output files or plots will be produced (i.e. less time-consuming).

#trace_analysis_script2.R
This script uses a reactive elasticity technique to compute the VM allocations for different DCs necessary to accomodate local as well as global demands.

Example:

```bash
Rscript trace_analysis_script1.R --src_dir /traces/day1/scaled --dst_dir /traces/day1/boxyplots --interval 60 --capacities 0,15000,30000,45000,55000,60000
```

This command will read all *.strace files in the "/traces/day1/scaled/" directory and perform VM allocations for the local as well as global rates. These allocations will be made based on the provided DC 'capacities' corresponding to the different cluster sizes. The elasticity technique will be reactive to rates average across a 60 second interval. The output plots depicting the VM capacities will be produced in "/traces/day1/boxyplots" directory.

```bash
Rscript trace_analysis_script1.R --src_dir /traces/day1/target --dst_dir /traces/day1/target --interval 60 --capacities 0,15000,30000,45000,55000,60000 --scalingfactor 666
```

This command will read all *.trace files in the "/traces/day1/" directory and scale the average rates for these traces based on the provided scaling factor. The same outputs will be produced as in the previous command.

