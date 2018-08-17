#!/bin/bash


echo "" > jobs
for target in 100 1000 
do
        for duration in 600
        do
                echo "./create_ycsb_trace.R --duration $duration --rate $target --arrival_distr poisson" >> jobs
        done
done

cat jobs |  parallel

mkdir ./samples/syn -p
mv ./samples/*.trace ././samples/syn
