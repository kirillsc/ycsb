/**
 * Copyright (c) 2013-2015 YCSB contributors. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may not
 * use this file except in compliance with the License. You may obtain a copy of
 * the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
 * License for the specific language governing permissions and limitations under
 * the License. See accompanying LICENSE file.
 *
 * Submitted by Chrisjan Matser on 10/11/2010.
 */
package com.yahoo.ycsb.db;

import com.datastax.driver.core.*;
import com.datastax.driver.core.policies.*;
import com.datastax.driver.core.querybuilder.Insert;
import com.datastax.driver.core.querybuilder.QueryBuilder;
import com.datastax.driver.core.querybuilder.Select;

import com.google.common.util.concurrent.ListenableFuture;
import com.yahoo.ycsb.ByteArrayByteIterator;
import com.yahoo.ycsb.ByteIterator;
import com.yahoo.ycsb.DB;
import com.yahoo.ycsb.DBException;
import com.yahoo.ycsb.Status;

import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;
import java.util.Vector;
import java.util.concurrent.atomic.AtomicInteger;


import java.net.InetSocketAddress;
import java.util.List;
import java.util.ArrayList;

/**
 * Cassandra 2.x CQL client.
 *
 * See {@code cassandra2/README.md} for details.
 *
 * @author cmatser
 */
public class CassandraCQLClient extends DB {

  private static Cluster cluster = null;
  private static Session session = null;

  private static ConsistencyLevel readConsistencyLevel = ConsistencyLevel.ONE;
  private static ConsistencyLevel writeConsistencyLevel = ConsistencyLevel.ONE;

  public static final String YCSB_KEY = "y_id";
  public static final String KEYSPACE_PROPERTY = "cassandra.keyspace";
  public static final String KEYSPACE_PROPERTY_DEFAULT = "ycsb";
  public static final String USERNAME_PROPERTY = "cassandra.username";
  public static final String PASSWORD_PROPERTY = "cassandra.password";

  public static final String HOSTS_PROPERTY = "hosts";
  public static final String PORT_PROPERTY = "port";
  public static final String PORT_PROPERTY_DEFAULT = "9042";

  public static final String READ_CONSISTENCY_LEVEL_PROPERTY =
      "cassandra_readconsistencylevel";
  public static final String READ_CONSISTENCY_LEVEL_PROPERTY_DEFAULT = "ONE";
  public static final String WRITE_CONSISTENCY_LEVEL_PROPERTY =
      "cassandra_writeconsistencylevel";
  public static final String WRITE_CONSISTENCY_LEVEL_PROPERTY_DEFAULT = "ONE";

  public static final String MAX_CONNECTIONS_PROPERTY =
      "cassandra.maxconnections";
  public static final String CORE_CONNECTIONS_PROPERTY =
      "cassandra.coreconnections";
  public static final String CONNECT_TIMEOUT_MILLIS_PROPERTY =
      "cassandra.connecttimeoutmillis";
  public static final String READ_TIMEOUT_MILLIS_PROPERTY =
      "cassandra.readtimeoutmillis";

  public static final String TRACING_PROPERTY = "cassandra.tracing";
  public static final String TRACING_PROPERTY_DEFAULT = "false";

  public static final String NEW_CONNECTION_THRESHOLD_LOCAL_KEY =
      "driver_newconnection_threshold_local";
  public static final String NEW_CONNECTION_THRESHOLD_REMOTE_KEY =
      "driver_newconnection_threshold_remote";

  public static final String MAX_REQUESTS_PER_CONNECTION_LOCAL_KEY =
      "driver_maxrequests_perconnection_local";
  public static final String MAX_REQUESTS_PER_CONNECTION_REMOTE_KEY =
      "driver_maxrequests_perconnection_remote";
  public static final String MAX_QUEUE_SIZE =
      "driver_maxqueuesize";
  public static final String DRIVER_ARGS =
      "driver_args";
  public static final String DRIVER_LOADBALANCER =
      "driver_loadbalancer";
  public static final String DRIVER_RETRY =
      "driver_retry";

  // Options for RateAndServiceTimeAwarePolicy (KURMA)
  public static final String DC_LATENCY_MATRIX = "dc_latency_matrix";

  /**
   * Count the number of times initialized to teardown on the last
   * {@link #cleanup()}.
   */
  private static final AtomicInteger INIT_COUNT = new AtomicInteger(0);

  private static boolean debug = false;

  private static boolean trace = false;

  /**
   * Initialize any state for this DB. Called once per DB instance; there is one
   * DB instance per client thread.
   */
  @Override
  public void init() throws DBException {
    // Keep track of number of calls to init (for later cleanup)
    INIT_COUNT.incrementAndGet();
    // Synchronized so that we only have a single
    // cluster/session instance for all the threads.
    synchronized (INIT_COUNT) {
      // Check if the cluster has already been initialized
      if (cluster != null) {
        return;
      }
      try {
        debug =
            Boolean.parseBoolean(getProperties().getProperty("debug", "false"));
        trace = Boolean.valueOf(getProperties().getProperty(
            TRACING_PROPERTY, TRACING_PROPERTY_DEFAULT));

        String host = getProperties().getProperty(HOSTS_PROPERTY);
        if (host == null) {
          throw new DBException(String.format(
              "Required property \"%s\" missing for CassandraCQLClient",
              HOSTS_PROPERTY));
        }
        String[] hosts = host.split(",");
        String port = getProperties().getProperty(PORT_PROPERTY, PORT_PROPERTY_DEFAULT);

        List<InetSocketAddress> whiteList = new ArrayList<InetSocketAddress>();
        String coordinators = getProperties().getProperty("coordinators");
        if (coordinators != null){
          for (String c: coordinators.split(" ")){
            whiteList.add(new InetSocketAddress(c, 9042));
          }
          System.err.println("Coordinators:");
          for (InetSocketAddress i: whiteList){
            System.err.println("\t"+i.toString());
          }
        }


        LoadBalancingPolicy loadBalancingPolicy;
        RetryPolicy retryPolicy;
        SpeculativeExecutionPolicy speculativePolicy;

        if(getProperties().getProperty(DRIVER_RETRY, "default").equals("disabled"))
        {
          retryPolicy = FallthroughRetryPolicy.INSTANCE;
        }
        else
        {
          retryPolicy = DefaultRetryPolicy.INSTANCE;
        }


        String username = getProperties().getProperty(USERNAME_PROPERTY);
        String password = getProperties().getProperty(PASSWORD_PROPERTY);
        String keyspace = getProperties().getProperty(KEYSPACE_PROPERTY,
            KEYSPACE_PROPERTY_DEFAULT);
        readConsistencyLevel = ConsistencyLevel.valueOf(
            getProperties().getProperty(READ_CONSISTENCY_LEVEL_PROPERTY,
                READ_CONSISTENCY_LEVEL_PROPERTY_DEFAULT));
        writeConsistencyLevel = ConsistencyLevel.valueOf(
            getProperties().getProperty(WRITE_CONSISTENCY_LEVEL_PROPERTY,
                WRITE_CONSISTENCY_LEVEL_PROPERTY_DEFAULT));

        System.err.println("KBG - YCSB branch [Tectonic], CQL driver version: " +
            Cluster.getDriverVersion());
        System.err.println("KBG - ReadConsistencyLevel: " + readConsistencyLevel);
        System.err.println("KBG - WriteConsistencyLevel: " + writeConsistencyLevel);

        String loadBalancer = getProperties().getProperty(DRIVER_LOADBALANCER, "roundrobin");
        if ((username != null) && !username.isEmpty()) {
          System.err.println("KBG - YCSB-1 ((username != null) && !username.isEmpty())");
          cluster = Cluster.builder().withCredentials(username, password)
              .withPort(Integer.valueOf(port)).addContactPoints(hosts).build();
        } else if (whiteList.size() > 0) {
          String includedCoordinators = "";

          for (InetSocketAddress coords : whiteList) {
            includedCoordinators += coords.toString();
          }
          System.err.println("KBG - YCSB-2 whiteList: " + includedCoordinators);
          loadBalancingPolicy = new RoundRobinPolicy();

          cluster = Cluster.builder()
              .withPort(Integer.valueOf(port))
              .withLoadBalancingPolicy(new WhiteListPolicy(loadBalancingPolicy, whiteList))
              .withAddressTranslator(new EC2MultiRegionAddressTranslator())
              .withRetryPolicy(retryPolicy)
              .addContactPoints(hosts).build();

        } else if (loadBalancer.equals("static")) {
          System.err.println("KBG - LoadBalancer static");

          float remoteRate = Float.parseFloat(getProperties().getProperty("remoterate", "1.0"));
          String localDC = getProperties().getProperty("localdc", "datacenter1");

          loadBalancingPolicy = DCAwareStaticMappingPolicy.builder().withLocalDc(localDC)
              .withRemoteDcRate(remoteRate).build();

          cluster = Cluster.builder()
              .withPort(Integer.valueOf(port))
              .withLoadBalancingPolicy(loadBalancingPolicy)
              .withAddressTranslator(new EC2MultiRegionAddressTranslator())
              .withRetryPolicy(retryPolicy)
              .addContactPoints(hosts).build();

        } else if (loadBalancer.equals("drc")) {
          System.err.println("KBG - YCSB-4 DRC");

          String dc_latency_matrix = getProperties().getProperty(DC_LATENCY_MATRIX,
            "3,DC1,DC2,DC3,0,5,7,5,0,2,7,2,0");

          String driver_args = getProperties().getProperty(DRIVER_ARGS,
            "");

          loadBalancingPolicy = RateAndServiceTimeAwarePolicy.builder()
              .withDCLatencyMatrix(dc_latency_matrix)
              .withArgs(driver_args)
              .build();

          cluster = Cluster.builder()
              .withPort(Integer.valueOf(port))
              .withLoadBalancingPolicy(loadBalancingPolicy)
              .withAddressTranslator(new EC2MultiRegionAddressTranslator())
              .withRetryPolicy(retryPolicy)
              .addContactPoints(hosts).build();


        } else if (loadBalancer.equals("latency")) {
          System.err.println("KBG - YCSB-5 Latency Aware");

          LatencyAwarePolicy latencyAwarePolicy = LatencyAwarePolicy.builder(new RoundRobinPolicy())
                .withMininumMeasurements(1) // This value taken from Class tests
                .build();

          cluster = Cluster.builder()
              .withPort(Integer.valueOf(port))
              .withLoadBalancingPolicy(latencyAwarePolicy)
              .withAddressTranslator(new EC2MultiRegionAddressTranslator())
              .withRetryPolicy(retryPolicy)
              .addContactPoints(hosts).build();


        } else if (loadBalancer.equals("dcrr")) {
          System.err.println("KBG - YCSB-6 Local DC Round Robin");


          String localDC = getProperties().getProperty("localdc", "datacenter1");

          cluster = Cluster.builder()
              .withPort(Integer.valueOf(port))
              .withLoadBalancingPolicy(DCAwareRoundRobinPolicy.builder().withLocalDc(localDC).build())
              .withAddressTranslator(new EC2MultiRegionAddressTranslator())
              .withRetryPolicy(retryPolicy)
              .addContactPoints(hosts)
              .build();


        } else {
          System.err.println("KBG - YCSB-7 default option (round robin)" + loadBalancer);
          // cluster = Cluster.builder().withPort(Integer.valueOf(port))
          //     .addContactPoints(hosts).build();

          loadBalancingPolicy = new RoundRobinPolicy();

          cluster = Cluster.builder()
              .withPort(Integer.valueOf(port))
              .withLoadBalancingPolicy(loadBalancingPolicy)
              .withAddressTranslator(new EC2MultiRegionAddressTranslator())
              .withRetryPolicy(retryPolicy)
              .addContactPoints(hosts).build();
        }


        String maxConnections = getProperties().getProperty(
            MAX_CONNECTIONS_PROPERTY);
        if (maxConnections != null) {
          cluster.getConfiguration().getPoolingOptions()
              .setMaxConnectionsPerHost(HostDistance.LOCAL,
              Integer.valueOf(maxConnections));
        }
        String coreConnections = getProperties().getProperty(
            CORE_CONNECTIONS_PROPERTY);
        if (coreConnections != null) {
          cluster.getConfiguration().getPoolingOptions()
              .setCoreConnectionsPerHost(HostDistance.LOCAL,
              Integer.valueOf(coreConnections));
        }
        String connectTimoutMillis = getProperties().getProperty(
            CONNECT_TIMEOUT_MILLIS_PROPERTY);
        if (connectTimoutMillis != null) {
          cluster.getConfiguration().getSocketOptions()
              .setConnectTimeoutMillis(Integer.valueOf(connectTimoutMillis));
        }
        String readTimoutMillis = getProperties().getProperty(
            READ_TIMEOUT_MILLIS_PROPERTY);
        if (readTimoutMillis != null) {
          cluster.getConfiguration().getSocketOptions()
              .setReadTimeoutMillis(Integer.valueOf(readTimoutMillis));
        }
        String prop = getProperties().getProperty(NEW_CONNECTION_THRESHOLD_LOCAL_KEY);
        if (prop != null) {
          cluster.getConfiguration().getPoolingOptions()
              .setNewConnectionThreshold(HostDistance.LOCAL, Integer.parseInt(prop));
          System.err.println("Setting NEW_CONNECTION_THRESHOLD_LOCAL_KEY to " + prop);
        }
        prop = getProperties().getProperty(NEW_CONNECTION_THRESHOLD_REMOTE_KEY);
        if (prop != null) {
          cluster.getConfiguration().getPoolingOptions()
              .setNewConnectionThreshold(HostDistance.REMOTE, Integer.parseInt(prop));
          System.err.println("Setting NEW_CONNECTION_THRESHOLD_REMOTE_KEY to " + prop);
        }
        prop = getProperties().getProperty(MAX_REQUESTS_PER_CONNECTION_LOCAL_KEY);
        if (prop != null) {
          cluster.getConfiguration().getPoolingOptions()
              .setMaxRequestsPerConnection(HostDistance.LOCAL, Integer.parseInt(prop));
          System.err.println("Setting MAX_REQUESTS_PER_CONNECTION_LOCAL_KEY to " + prop);
        }
        prop = getProperties().getProperty(MAX_REQUESTS_PER_CONNECTION_REMOTE_KEY);
        if (prop != null) {
          cluster.getConfiguration().getPoolingOptions()
              .setMaxRequestsPerConnection(HostDistance.REMOTE, Integer.parseInt(prop));
          System.err.println("Setting MAX_REQUESTS_PER_CONNECTION_REMOTE_KEY to " + prop);
        }
        prop = getProperties().getProperty(MAX_QUEUE_SIZE);
        if (prop != null) {
          cluster.getConfiguration().getPoolingOptions()
              .setMaxQueueSize(Integer.parseInt(prop));
          System.err.println("Setting MAX_QUEUE_SIZE to " + prop);
        }

        Metadata metadata = cluster.getMetadata();
        System.err.printf("Connected to cluster: %s\n",
            metadata.getClusterName());
        for (Host discoveredHost : metadata.getAllHosts()) {
          System.err.printf("Datacenter: %s; Host: %s; Rack: %s\n",
              discoveredHost.getDatacenter(), discoveredHost.getAddress(),
              discoveredHost.getRack());
        }
        session = cluster.connect(keyspace);
      } catch (Exception e) {
        throw new DBException(e);
      }
    } // synchronized
  }

  /**
   * Cleanup any state for this DB. Called once per DB instance; there is one DB
   * instance per client thread.
   */
  @Override
  public void cleanup() throws DBException {
    synchronized (INIT_COUNT) {
      final int curInitCount = INIT_COUNT.decrementAndGet();
      if (curInitCount <= 0) {
        session.close();
        cluster.close();
        cluster = null;
        session = null;
      }
      if (curInitCount < 0) {
        // This should never happen.
        throw new DBException(
            String.format("initCount is negative: %d", curInitCount));
      }
    }
  }

  /**
   * Read a record from the database. Each field/value pair from the result will
   * be stored in a HashMap.
   *
   * @param table
   *          The name of the table
   * @param key
   *          The record key of the record to read.
   * @param fields
   *          The list of fields to read, or null for all of them
   * @param result
   *          A HashMap of field/value pairs for the result
   * @return Zero on success, a non-zero error code on error
   */
  @Override
  public Status read(String table, String key, Set<String> fields,
      HashMap<String, ByteIterator> result) {
    try {
      Statement stmt;
      Select.Builder selectBuilder;

      if (fields == null) {
        selectBuilder = QueryBuilder.select().all();
      } else {
        selectBuilder = QueryBuilder.select();
        for (String col : fields) {
          ((Select.Selection) selectBuilder).column(col);
        }
      }

      stmt = selectBuilder.from(table).where(QueryBuilder.eq(YCSB_KEY, key))
          .limit(1);
      stmt.setConsistencyLevel(readConsistencyLevel);

      if (debug) {
        System.err.println(stmt.toString());
      }
      if (trace) {
        stmt.enableTracing();
      }

      ResultSet rs = session.execute(stmt);

      if (rs.isExhausted()) {
        return Status.NOT_FOUND;
      }

      // Should be only 1 row
      Row row = rs.one();
      ColumnDefinitions cd = row.getColumnDefinitions();

      for (ColumnDefinitions.Definition def : cd) {
        ByteBuffer val = row.getBytesUnsafe(def.getName());
        if (val != null) {
          result.put(def.getName(), new ByteArrayByteIterator(val.array()));
        } else {
          result.put(def.getName(), null);
        }
      }

      return Status.OK;

    } catch (Exception e) {
      e.printStackTrace();
      System.err.println("Error reading key: " + key);
      return Status.ERROR;
    }

  }

  /**
   * Read a record asynchronously from the database. Each field/value pair from the result will
   * be stored in a HashMap.
   *
   * @param table
   *          The name of the table
   * @param key
   *          The record key of the record to read.
   * @param fields
   *          The list of fields to read, or null for all of them
   * @return Zero on success, a non-zero error code on error
   */
  @Override
  public ResultSetFuture readAsync(String table, String key, Set<String> fields, HashMap<String, ByteIterator> result) {
      Statement stmt;
      Select.Builder selectBuilder;

      if (fields == null) {
        selectBuilder = QueryBuilder.select().all();
      } else {
        selectBuilder = QueryBuilder.select();
        for (String col : fields) {
          ((Select.Selection) selectBuilder).column(col);
        }
      }

      stmt = selectBuilder.from(table).where(QueryBuilder.eq(YCSB_KEY, key))
          .limit(1);
      stmt.setConsistencyLevel(readConsistencyLevel);

      if (debug) {
        System.err.println(stmt.toString());
      }
      if (trace) {
        stmt.enableTracing();
      }

      ResultSetFuture rsf = session.executeAsync(stmt);

      return rsf;

  }

  @Override
  public Status parseReadAsync(String key, Object returned, HashMap<String, ByteIterator> result) {
    try {
      ResultSet rs = (ResultSet) returned;
      if (rs.isExhausted()) {
        return Status.NOT_FOUND;
      }

      // Should be only 1 row
      Row row = rs.one();
      ColumnDefinitions cd = row.getColumnDefinitions();

      for (ColumnDefinitions.Definition def : cd) {
        ByteBuffer val = row.getBytesUnsafe(def.getName());
        if (val != null) {
          result.put(def.getName(), new ByteArrayByteIterator(val.array()));
        } else {
          result.put(def.getName(), null);
        }
      }

      return Status.OK;

    } catch (Exception e) {
      e.printStackTrace();
      System.err.println("Error reading key: " + key);
      return Status.ERROR;
    }
  }

  /**
   * Perform a range scan for a set of records in the database. Each field/value
   * pair from the result will be stored in a HashMap.
   *
   * Cassandra CQL uses "token" method for range scan which doesn't always yield
   * intuitive results.
   *
   * @param table
   *          The name of the table
   * @param startkey
   *          The record key of the first record to read.
   * @param recordcount
   *          The number of records to read
   * @param fields
   *          The list of fields to read, or null for all of them
   * @param result
   *          A Vector of HashMaps, where each HashMap is a set field/value
   *          pairs for one record
   * @return Zero on success, a non-zero error code on error
   */
  @Override
  public Status scan(String table, String startkey, int recordcount,
      Set<String> fields, Vector<HashMap<String, ByteIterator>> result) {

    try {
      Statement stmt;
      Select.Builder selectBuilder;

      if (fields == null) {
        selectBuilder = QueryBuilder.select().all();
      } else {
        selectBuilder = QueryBuilder.select();
        for (String col : fields) {
          ((Select.Selection) selectBuilder).column(col);
        }
      }

      stmt = selectBuilder.from(table);

      // The statement builder is not setup right for tokens.
      // So, we need to build it manually.
      String initialStmt = stmt.toString();
      StringBuilder scanStmt = new StringBuilder();
      scanStmt.append(initialStmt.substring(0, initialStmt.length() - 1));
      scanStmt.append(" WHERE ");
      scanStmt.append(QueryBuilder.token(YCSB_KEY));
      scanStmt.append(" >= ");
      scanStmt.append("token('");
      scanStmt.append(startkey);
      scanStmt.append("')");
      scanStmt.append(" LIMIT ");
      scanStmt.append(recordcount);

      stmt = new SimpleStatement(scanStmt.toString());
      stmt.setConsistencyLevel(readConsistencyLevel);

      if (debug) {
        System.err.println(stmt.toString());
      }
      if (trace) {
        stmt.enableTracing();
      }

      ResultSet rs = session.execute(stmt);

      HashMap<String, ByteIterator> tuple;
      while (!rs.isExhausted()) {
        Row row = rs.one();
        tuple = new HashMap<String, ByteIterator>();

        ColumnDefinitions cd = row.getColumnDefinitions();

        for (ColumnDefinitions.Definition def : cd) {
          ByteBuffer val = row.getBytesUnsafe(def.getName());
          if (val != null) {
            tuple.put(def.getName(), new ByteArrayByteIterator(val.array()));
          } else {
            tuple.put(def.getName(), null);
          }
        }

        result.add(tuple);
      }

      return Status.OK;

    } catch (Exception e) {
      e.printStackTrace();
      System.err.println("Error scanning with startkey: " + startkey);
      return Status.ERROR;
    }

  }

  /**
   * Update a record in the database. Any field/value pairs in the specified
   * values HashMap will be written into the record with the specified record
   * key, overwriting any existing values with the same field name.
   *
   * @param table
   *          The name of the table
   * @param key
   *          The record key of the record to write.
   * @param values
   *          A HashMap of field/value pairs to update in the record
   * @return Zero on success, a non-zero error code on error
   */
  @Override
  public Status update(String table, String key,
      HashMap<String, ByteIterator> values) {
    // Insert and updates provide the same functionality
    return insert(table, key, values);
  }

  /**
   * Insert a record in the database. Any field/value pairs in the specified
   * values HashMap will be written into the record with the specified record
   * key.
   *
   * @param table
   *          The name of the table
   * @param key
   *          The record key of the record to insert.
   * @param values
   *          A HashMap of field/value pairs to insert in the record
   * @return Zero on success, a non-zero error code on error
   */
  @Override
  public Status insert(String table, String key,
      HashMap<String, ByteIterator> values) {

    try {
      Insert insertStmt = QueryBuilder.insertInto(table);

      // Add key
      insertStmt.value(YCSB_KEY, key);

      // Add fields
      for (Map.Entry<String, ByteIterator> entry : values.entrySet()) {
        Object value;
        ByteIterator byteIterator = entry.getValue();
        value = byteIterator.toString();

        insertStmt.value(entry.getKey(), value);
      }

      insertStmt.setConsistencyLevel(writeConsistencyLevel);

      if (debug) {
        System.err.println(insertStmt.toString());
      }
      if (trace) {
        insertStmt.enableTracing();
      }

      session.execute(insertStmt);

      return Status.OK;
    } catch (Exception e) {
      e.printStackTrace();
    }

    return Status.ERROR;
  }

  /**
   * Delete a record from the database.
   *
   * @param table
   *          The name of the table
   * @param key
   *          The record key of the record to delete.
   * @return Zero on success, a non-zero error code on error
   */
  @Override
  public Status delete(String table, String key) {

    try {
      Statement stmt;

      stmt = QueryBuilder.delete().from(table)
          .where(QueryBuilder.eq(YCSB_KEY, key));
      stmt.setConsistencyLevel(writeConsistencyLevel);

      if (debug) {
        System.err.println(stmt.toString());
      }
      if (trace) {
        stmt.enableTracing();
      }

      session.execute(stmt);

      return Status.OK;
    } catch (Exception e) {
      e.printStackTrace();
      System.err.println("Error deleting key: " + key);
    }

    return Status.ERROR;
  }

  @Override
  public ListenableFuture updateAsync(String table, String keyname, HashMap<String, ByteIterator> values) {
    return insertAsync(table, keyname, values);
  }

  @Override
  public ListenableFuture insertAsync(String table, String dbkey, HashMap<String, ByteIterator> values) {
      Insert insertStmt = QueryBuilder.insertInto(table);

      // Add key
      insertStmt.value(YCSB_KEY, dbkey);

      // Add fields
      for (Map.Entry<String, ByteIterator> entry : values.entrySet()) {
        Object value;
        ByteIterator byteIterator = entry.getValue();
        value = byteIterator.toString();

        insertStmt.value(entry.getKey(), value);
      }

      insertStmt.setConsistencyLevel(writeConsistencyLevel);

      if (debug) {
        System.err.println(insertStmt.toString());
      }
      if (trace) {
        insertStmt.enableTracing();
      }

      ResultSetFuture rsf = session.executeAsync(insertStmt);

      return rsf;
  }

}
