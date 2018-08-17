#!/usr/bin/python
import os
import argparse
import pandas as pd
import numpy as np
import logging

import SimPy.Simulation as Simulation

import matplotlib.pyplot as plt
from matplotlib import dates

from pytools.common.common import get_files_matching_mask

logging.basicConfig(format="%(filename).7s.py (%(funcName).5s):[%(lineno)4d] %(asctime)s %(levelname)7s || %(message)s",
    datefmt='%H:%M:%S', level=logging.INFO)


class CircularRateCounter(Simulation.Process):

    def __init__(self, id, window, n_segments=10):

        self.rate = 0
        self.id = id

        self.index = 0
        self.total_samples = 0

        self.window = window
        self.n_segments = n_segments

        self.bins = [0 for i in range(self.n_segments)]

        Simulation.Process.__init__(self, name=self.id)
        Simulation.activate(self, self.run(), at=Simulation.now())

    def get_rate(self):
        # TODO: which one of these is correct?
        return self.total_samples
        # return self.rate

    def run(self):
        while True:
            yield Simulation.hold, self, self.window / self.n_segments

            # <1.> Move head to the old tail position
            self.index += 1
            new_head_index = self.index % self.n_segments

            # <2.> Erase old samples that are older than X
            self.total_samples -= self.bins[new_head_index]
            self.bins[new_head_index] = 0

            # <3.> Compute new rate
            self.rate = self.total_samples


    def add(self, count=1):
        self.bins[ self.index % self.n_segments ] += count
        self.total_samples += count



class Runner(Simulation.Process):
    def __init__(self, df):
        self.df = df
        self.index = 0

        self.rate_counters = {}
        self.rate_counters["1sec"] = CircularRateCounter("counter", 1, 1)
        self.rate_counters["10sec"] = CircularRateCounter("counter", 10, 10)
        self.rate_counters["1min"] = CircularRateCounter("counter", 60, 60)
        # self.rate_counters["1min"] = CircularRateCounter("counter", 60, 60)

        self.df["1sec"] = [0]*len(df)
        self.df["10sec"] = [0]*len(df)
        self.df["1min"] = [0]*len(df)
            # rate_counters["1"] = CircularRateCounter("counter", 60, 60)

        self.rates = {}
        self.rates["1sec"] = []
        self.rates["10sec"] = []
        self.rates["1min"] = []


        Simulation.Process.__init__(self, name="runner")
        Simulation.activate(self, self.run(), at=Simulation.now())

    def apply_rates(self):
        """ This way it is much faster than to apply each individual row at run time"""
        for rate_name, rates in self.rates.iteritems():
            rates.append(0) # compensate for 1 last missing element
            self.df[rate_name] = rates


    def run(self):
        while self.index + 1 < len(self.df):

            true_now = Simulation.now()
            expected_now = self.df.ix[self.index , "relative_time_sec"]

            next_time = self.df.ix[self.index + 1, "relative_time_sec"]
            sleeping = next_time - true_now

            for rate_name, counter in self.rate_counters.iteritems():
                counter.add()

                # self.df.ix[self.index, rate_name] = counter.get_rate()
                self.rates[rate_name].append(counter.get_rate())


            # print "now, expected [%5s %5s %5s] next, sleep [%3s] next index [%3i]" % (
            #     true_now, expected_now, next_time, sleeping, self.index)
            assert true_now == expected_now

            yield Simulation.hold, self, sleeping
            self.index += 1



def group_data_by_column(df, column_name):

    df_dic = {}
    for c in set(df[column_name]):
        df_dic[c] = df[df[column_name] == c]
    return df_dic

def sort_by_datetime(dfs):

    for i, df in enumerate(dfs):
        logging.info("Sorting dataframe - %i ", i)
        df = df.sort_values(['time_sec'], ascending=True)
        df.index = range(0, len(df))
        dfs[i] = df

    return dfs

if __name__ == '__main__':

    parser = argparse.ArgumentParser(""" """)

    parser.add_argument("--src_file", default="", type=str)
    parser.add_argument("--out_folder", default="", type=str)
    FLAGS = parser.parse_args()

    logging.info("Reading input data [%s]", FLAGS.src_file)
    df = pd.read_csv(FLAGS.src_file, sep=" ",
        names=["time_sec", "region"],
        dtype={"time_sec":np.uint64, "region":str},
        error_bad_lines=True,
        skip_blank_lines=False,
        )

    # df = df[:10000]

    # convert to a dictionary
    logging.info("Grouping by regions")
    dfs = group_data_by_column(df, "region")

    # sort each column
    logging.info("Sorting by time stamps")
    for reg, d in dfs.iteritems():
        dfs[reg] = sort_by_datetime([d])[0]

    # add delta time
    logging.info("Computing delta time column")
    for reg, d in dfs.iteritems():
        first_timestamp = d.ix[0, "time_sec"]
        d["relative_time_sec"] = d.apply(
            lambda x: int(x["time_sec"] - first_timestamp), axis=1)

    # add inter-arrival interval
    logging.info("Computing interarrival time column")
    for reg, d in dfs.iteritems():
        rels = list(d["relative_time_sec"])
        res = [0]
        for i in range(0, len(rels) - 1):
            res.append(rels[i+1] - rels[i])
        d["interarrival_sec"] = res



    for reg, d in dfs.iteritems():
        Simulation.initialize()
        r = Runner(d)
        until = d.ix[d.index[-1]]["relative_time_sec"]

        logging.info("---Simulating region [%s] unitl [%i] samples [%i]",
            reg, until, len(d))

        Simulation.simulate(until=until)

        r.apply_rates()

        oname = os.path.join(FLAGS.out_folder, "%s_reg%s.data" % (os.path.basename(FLAGS.src_file), reg))
        r.df.to_csv(oname, sep=" ")


