/**
 * Copyright (c) 2010 Yahoo! Inc., 2016-2017 YCSB contributors. All rights reserved.
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

package com.yahoo.ycsb;

import com.google.common.util.concurrent.*;
import com.yahoo.ycsb.measurements.Measurements;
import org.apache.htrace.core.TraceScope;
import org.apache.htrace.core.Tracer;

import java.nio.ByteBuffer;
import java.sql.ResultSet;
import java.util.*;
import java.util.concurrent.Executors;

/**
 * Wrapper around a "real" DB that measures latencies and counts return codes.
 * Also reports latency separately between OK and failed operations.
 */
public class DBWrapper extends DB {
  private final DB db;
  private final Measurements measurements;
  private final Tracer tracer;

  private boolean reportLatencyForEachError = false;
  private HashSet<String> latencyTrackedErrors = new HashSet<String>();

  private boolean measurementsDedicatedPool;
  private int measurementsThreads;
  private ListeningExecutorService les;

  private static final String REPORT_LATENCY_FOR_EACH_ERROR_PROPERTY = "reportlatencyforeacherror";
  private static final String REPORT_LATENCY_FOR_EACH_ERROR_PROPERTY_DEFAULT = "false";

  private static final String RAW_OPTIMIZED_DEDICATED_THREADPOOL = "measurement.raw.dedicated.threadpool";
  private static final String RAW_OPTIMIZED_DEDICATED_THREADPOOL_DEFAULT = "false";

  private static final String RAW_OPTIMIZED_THREADCOUNT = "measurement.raw.threadcount";
  private static final String RAW_OPTIMIZED_THREADCOUNT_DEFAULT = "16";

  private static final String LATENCY_TRACKED_ERRORS_PROPERTY = "latencytrackederrors";

  private final String scopeStringCleanup;
  private final String scopeStringDelete;
  private final String scopeStringInit;
  private final String scopeStringInsert;
  private final String scopeStringRead;
  private final String scopeStringScan;
  private final String scopeStringUpdate;

  public DBWrapper(final DB db, final Tracer tracer) {
    this.db = db;
    measurements = Measurements.getMeasurements();
    this.tracer = tracer;
    final String simple = db.getClass().getSimpleName();
    scopeStringCleanup = simple + "#cleanup";
    scopeStringDelete = simple + "#delete";
    scopeStringInit = simple + "#init";
    scopeStringInsert = simple + "#insert";
    scopeStringRead = simple + "#read";
    scopeStringScan = simple + "#scan";
    scopeStringUpdate = simple + "#update";
    this.reportLatencyForEachError = Boolean.parseBoolean(getProperties().
        getProperty(REPORT_LATENCY_FOR_EACH_ERROR_PROPERTY,
            REPORT_LATENCY_FOR_EACH_ERROR_PROPERTY_DEFAULT));
    this.measurementsDedicatedPool = Boolean.parseBoolean(getProperties().
        getProperty(RAW_OPTIMIZED_DEDICATED_THREADPOOL,
            RAW_OPTIMIZED_DEDICATED_THREADPOOL_DEFAULT));
    this.measurementsThreads = Integer.parseInt(getProperties()
        .getProperty(RAW_OPTIMIZED_THREADCOUNT, RAW_OPTIMIZED_THREADCOUNT_DEFAULT));

    if(this.measurementsDedicatedPool)
    {
      System.err.println("Creating dedicated threadpool for rawoptimized measurements with " + this.measurementsThreads
      + " threads");
      this.les = MoreExecutors.listeningDecorator(Executors.newFixedThreadPool(this.measurementsThreads));
    }
    else
    {
      this.les = null;
      getProperties().setProperty(RAW_OPTIMIZED_THREADCOUNT, "16");
    }
  }

  /**
   * Set the properties for this DB.
   */
  public void setProperties(Properties p) {
    db.setProperties(p);
  }

  /**
   * Get the set of properties for this DB.
   */
  public Properties getProperties() {
    return db.getProperties();
  }

  /**
   * Initialize any state for this DB.
   * Called once per DB instance; there is one DB instance per client thread.
   */
  public void init() throws DBException {
    try (final TraceScope span = tracer.newScope(scopeStringInit)) {
      db.init();

      this.reportLatencyForEachError = Boolean.parseBoolean(getProperties().
          getProperty(REPORT_LATENCY_FOR_EACH_ERROR_PROPERTY,
              REPORT_LATENCY_FOR_EACH_ERROR_PROPERTY_DEFAULT));

      if (!reportLatencyForEachError) {
        String latencyTrackedErrorsProperty = getProperties().getProperty(LATENCY_TRACKED_ERRORS_PROPERTY, null);
        if (latencyTrackedErrorsProperty != null) {
          this.latencyTrackedErrors = new HashSet<String>(Arrays.asList(
              latencyTrackedErrorsProperty.split(",")));
        }
      }

      // System.err.println("DBWrapper: report latency for each error is " +
      //     this.reportLatencyForEachError + " and specific error codes to track" +
      //     " for latency are: " + this.latencyTrackedErrors.toString());
    }
  }

  /**
   * Cleanup any state for this DB.
   * Called once per DB instance; there is one DB instance per client thread.
   */
  public void cleanup() throws DBException {
    try (final TraceScope span = tracer.newScope(scopeStringCleanup)) {
      long ist = measurements.getIntendedtartTimeNs();
      long st = System.nanoTime();
      db.cleanup();
      long en = System.nanoTime();
      measure("CLEANUP", Status.OK, ist, st, en);
    }
  }

  /**
   * Read a record from the database. Each field/value pair from the result
   * will be stored in a HashMap.
   *
   * @param table The name of the table
   * @param key The record key of the record to read.
   * @param fields The list of fields to read, or null for all of them
   * @param result A HashMap of field/value pairs for the result
   * @return The result of the operation.
   */
  public Status read(String table, String key, Set<String> fields,
                     HashMap<String, ByteIterator> result) {
    try (final TraceScope span = tracer.newScope(scopeStringRead)) {
      long ist = measurements.getIntendedtartTimeNs();
      long st = System.nanoTime();
      Status res = db.read(table, key, fields, result);
      long en = System.nanoTime();
      measure("READ", res, ist, st, en);
      measurements.reportStatus("READ", res);
      return res;
    }
  }

  /**
   * Read asynchronously a record from the database. Each field/value pair from the result
   * will be stored in a HashMap.
   *
   * @param table The name of the table
   * @param key The record key of the record to read.
   * @param fields The list of fields to read, or null for all of them
   * @param result A HashMap of field/value pairs for the result
   */
  public ListenableFuture readAsync(String table, final String key, Set<String> fields,
                     final HashMap<String, ByteIterator> result) {
    try (final TraceScope span = tracer.newScope(scopeStringRead)) {
      final long ist = measurements.getIntendedtartTimeNs();
      final long st = System.nanoTime();
      //Status res = db.read(table, key, fields, result);

      ListenableFuture future = db.readAsync(table, key, fields, result);


      Futures.addCallback(future,
          new FutureCallback<Object>() {
            @Override public void onSuccess(Object returned) {
              long en = System.nanoTime();
              Status res = db.parseReadAsync(key, returned, result);
              measure("READ", res, ist, st, en);
              measurements.reportStatus("READ", res);
            }

            @Override public void onFailure(Throwable t) {
              //Output some error message
            }
          },
          this.measurementsDedicatedPool ? this.les : MoreExecutors.sameThreadExecutor()
      );
    }
    return null;
  }

  @Override
  public Status parseReadAsync(String key, Object returned, HashMap<String, ByteIterator> result) {
    throw new UnsupportedOperationException();
  }

  /**
   * Perform a range scan for a set of records in the database.
   * Each field/value pair from the result will be stored in a HashMap.
   *
   * @param table The name of the table
   * @param startkey The record key of the first record to read.
   * @param recordcount The number of records to read
   * @param fields The list of fields to read, or null for all of them
   * @param result A Vector of HashMaps, where each HashMap is a set field/value pairs for one record
   * @return The result of the operation.
   */
  public Status scan(String table, String startkey, int recordcount,
                     Set<String> fields, Vector<HashMap<String, ByteIterator>> result) {
    try (final TraceScope span = tracer.newScope(scopeStringScan)) {
      long ist = measurements.getIntendedtartTimeNs();
      long st = System.nanoTime();
      Status res = db.scan(table, startkey, recordcount, fields, result);
      long en = System.nanoTime();
      measure("SCAN", res, ist, st, en);
      measurements.reportStatus("SCAN", res);
      return res;
    }
  }

  private void measure(String op, Status result, long intendedStartTimeNanos,
                       long startTimeNanos, long endTimeNanos) {
    String measurementName = op;
    if (result == null || !result.isOk()) {
      if (this.reportLatencyForEachError ||
          this.latencyTrackedErrors.contains(result.getName())) {
        measurementName = op + "-" + result.getName();
      } else {
        measurementName = op + "-FAILED";
      }
    }
    measurements.measure(measurementName,
        (int) ((endTimeNanos - startTimeNanos) / 1000));
    measurements.measureIntended(measurementName,
        (int) ((endTimeNanos - intendedStartTimeNanos) / 1000));
  }

  /**
   * Update a record in the database. Any field/value pairs in the specified values HashMap will be written into the
   * record with the specified record key, overwriting any existing values with the same field name.
   *
   * @param table The name of the table
   * @param key The record key of the record to write.
   * @param values A HashMap of field/value pairs to update in the record
   * @return The result of the operation.
   */
  public Status update(String table, String key,
                       HashMap<String, ByteIterator> values) {
    try (final TraceScope span = tracer.newScope(scopeStringUpdate)) {
      long ist = measurements.getIntendedtartTimeNs();
      long st = System.nanoTime();
      Status res = db.update(table, key, values);
      long en = System.nanoTime();
      measure("UPDATE", res, ist, st, en);
      measurements.reportStatus("UPDATE", res);
      return res;
    }
  }

  /**
   * Insert a record in the database. Any field/value pairs in the specified
   * values HashMap will be written into the record with the specified
   * record key.
   *
   * @param table The name of the table
   * @param key The record key of the record to insert.
   * @param values A HashMap of field/value pairs to insert in the record
   * @return The result of the operation.
   */
  public Status insert(String table, String key,
                       HashMap<String, ByteIterator> values) {
    try (final TraceScope span = tracer.newScope(scopeStringInsert)) {
      long ist = measurements.getIntendedtartTimeNs();
      long st = System.nanoTime();
      Status res = db.insert(table, key, values);
      long en = System.nanoTime();
      measure("INSERT", res, ist, st, en);
      measurements.reportStatus("INSERT", res);
      return res;
    }
  }

  /**
   * Delete a record from the database.
   *
   * @param table The name of the table
   * @param key The record key of the record to delete.
   * @return The result of the operation.
   */
  public Status delete(String table, String key) {
    try (final TraceScope span = tracer.newScope(scopeStringDelete)) {
      long ist = measurements.getIntendedtartTimeNs();
      long st = System.nanoTime();
      Status res = db.delete(table, key);
      long en = System.nanoTime();
      measure("DELETE", res, ist, st, en);
      measurements.reportStatus("DELETE", res);
      return res;
    }
  }

  @Override
  public ListenableFuture updateAsync(String table, String keyname, HashMap<String, ByteIterator> values) {
    try (final TraceScope span = tracer.newScope(scopeStringUpdate)) {
      final long ist = measurements.getIntendedtartTimeNs();
      final long st = System.nanoTime();
      //Status res = db.read(table, key, fields, result);

      ListenableFuture future = db.updateAsync(table, keyname, values);

      Futures.addCallback(future,
          new FutureCallback<Object>() {
            @Override public void onSuccess(Object returned) {
              long en = System.nanoTime();

              //FIXME For now, assume all requests are successful
              measure("UPDATE", Status.OK, ist, st, en);
              measurements.reportStatus("UPDATE", Status.OK);
            }

            @Override public void onFailure(Throwable t) {
              //Output some error message
            }
          },
          this.measurementsDedicatedPool ? this.les : MoreExecutors.sameThreadExecutor()
      );
    }
    return null;
  }

  @Override
  public ListenableFuture insertAsync(String table, String dbkey, HashMap<String, ByteIterator> values) {
    try (final TraceScope span = tracer.newScope(scopeStringInsert)) {
      final long ist = measurements.getIntendedtartTimeNs();
      final long st = System.nanoTime();
      //Status res = db.read(table, key, fields, result);

      ListenableFuture future = db.insertAsync(table, dbkey, values);

      Futures.addCallback(future,
          new FutureCallback<Object>() {
            @Override public void onSuccess(Object returned) {
              long en = System.nanoTime();

              //FIXME For now, assume all requests are successful
              measure("INSERT", Status.OK, ist, st, en);
              measurements.reportStatus("INSERT", Status.OK);
            }

            @Override public void onFailure(Throwable t) {
              //Output some error message
            }
          },
          this.measurementsDedicatedPool ? this.les : MoreExecutors.sameThreadExecutor()
      );
    }
    return null;
  }
}
