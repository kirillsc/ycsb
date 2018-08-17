/**
 * Copyright (c) 2015-2017 YCSB contributors All rights reserved.
 * <p>
 * Licensed under the Apache License, Version 2.0 (the "License"); you
 * may not use this file except in compliance with the License. You
 * may obtain a copy of the License at
 * <p>
 * http://www.apache.org/licenses/LICENSE-2.0
 * <p>
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
 * implied. See the License for the specific language governing
 * permissions and limitations under the License. See accompanying
 * LICENSE file.
 */

package com.yahoo.ycsb.measurements;

import com.yahoo.ycsb.measurements.exporter.MeasurementsExporter;

import java.io.*;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedList;
import java.util.Properties;

/**
 * This measurement class does nothing other than keeping counts
 * of the average latency. It is primarily used as a baseline
 * for testing the overheads imposed by the other measurement classes
 */
public class OneMeasurementNone extends OneMeasurement {

  private long totalOps;

  private double totalLatency;

  public OneMeasurementNone(String name, Properties props) {
    super(name);

    totalOps = 0;
    totalLatency = 0;
  }

  @Override
  public synchronized void measure(int latency) {
    totalOps += 1;
    totalLatency += latency;
  }

  @Override
  public void exportMeasurements(MeasurementsExporter exporter)
      throws IOException {
    exporter.write(getName(), "Total Operations", totalOps);
    exporter.write(
        getName(), "Average Latency (us)", totalLatency/totalOps);
  }

  @Override
  public synchronized String getSummary() {
    return "";
  }
}
