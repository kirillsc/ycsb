package com.yahoo.ycsb.workloads;

import java.util.LinkedHashMap;
import java.util.Properties;

import com.yahoo.ycsb.Client;
import com.yahoo.ycsb.DB;
import com.yahoo.ycsb.WorkloadException;
import com.yahoo.ycsb.generator.FileGenerator;

/**
 * Workload generator that replays a user-defined trace file
 * <p>
 * Properties to control the client:
 * </p>
 * <UL>
 * <LI><b>disksize</b>: how many bytes of storage can the disk store? (default 100,000,000)
 * <LI><b>occupancy</b>: what fraction of the available storage should be used? (default 0.9)
 * <LI><b>requestdistribution</b>: what distribution should be used to select the records to operate on
 * - uniform, zipfian or latest (default: histogram)
 * </ul>
 *
 *
 * @author waleed
 *
 */
public class TraceWorkload extends CoreWorkload {

  /**
   * The path of file to use for trace-type workloads.
   */
  private static final String TRACEFILE_PROPERTY="tracefile";

  /**
   * The default path of the trace file.
   */
  private static final String TRACEFILE_PROPERTY_DEFAULT="inputFile.txt";

  /**
   * The warmup period (in seconds) for the database. If workload is generated using a trace,
   * we set the sending rate during the warmup period to be equivalent to the rate of the 1st
   * minute from the provided trace. Otherwise, set according to the default target parameter.
   */
  private static final String WARMUP_PERIOD_PROPERTY="warmupperiod";

  private static final String WARMUP_PERIOD_INTERVALS_PROPERTY="warmupperiod_intervals";

  /**
   * The default warmup period (in seconds).
   */
  private static final String WARMUP_PERIOD_PROPERTY_DEFAULT="0";

  private static final String WARMUP_PERIOD_INTERVALS_PROPERTY_DEFAULT="5";

  /**
   * The number of YCSB client threads to run.
   */
  public static final String THREAD_COUNT_PROPERTY = "threadcount";

  private static String tracefile;

  private FileGenerator filegen;

  private long warmupperiod_ns;

  private int warmupperiod_intervals;

  private int warmuprate=-1;

  private int threadcount;

  private int warmupops=0; //total number of warmup operations

  private LinkedHashMap<Integer, Long> stepFunc; //step function for incrementing rates in warmup phase

  //private int current_warm=0;

  //private int current_trace=0;

  private int lineCount=0;

  @Override
  public void init(Properties p) throws WorkloadException {

    tracefile = p.getProperty(TRACEFILE_PROPERTY, TRACEFILE_PROPERTY_DEFAULT);
    filegen = new FileGenerator(tracefile);

    warmupperiod_ns = Long.parseLong(p.getProperty(WARMUP_PERIOD_PROPERTY, WARMUP_PERIOD_PROPERTY_DEFAULT))
        * 1000000000;

    warmupperiod_intervals = Integer.parseInt(p.getProperty(WARMUP_PERIOD_INTERVALS_PROPERTY, WARMUP_PERIOD_INTERVALS_PROPERTY_DEFAULT));

    threadcount = Integer.parseInt(p.getProperty(THREAD_COUNT_PROPERTY, "1"));

    System.err.println("Counting # of operations in trace.");
    //calculate the number of lines
    Long timestamp;
    lineCount = 0;
    while(true)
    {
      timestamp = readTimestampFromFile(filegen);

      if(timestamp == null)
        break;

      if(warmuprate == -1 && timestamp>=60000000000L)
        warmuprate = lineCount/60;

      lineCount++;
    }

    //Read entire trace if opcount==0
    int opcount=Integer.parseInt(p.getProperty(Client.OPERATION_COUNT_PROPERTY,"0"));

    if(opcount > lineCount) {
      System.err.println("[Warning] : operationcount parameter is larger than trace size." +
          " Experiment will terminate once end of trace is reached.");
    }

    System.err.println("Trace file has " + lineCount + " operations. Refreshing trace..");

    //Reload file
    filegen.reloadFile();

    if(warmuprate == -1 && warmupperiod_ns>0) {
      System.err.println("Error: Failure to start warmup phase. Trace duration is less than 1 minute.");
      System.exit(-1);
    }

    if(warmupperiod_ns>0) {

      System.err.println("Starting " + warmupperiod_ns/1000000000L
          + "s warmup phase. Target rate is " + warmuprate + " req/s");
      stepFunc = new LinkedHashMap<Integer, Long>();
      long stepinterval = warmupperiod_ns/warmupperiod_intervals;
      int stepincrement = warmuprate/warmupperiod_intervals/threadcount;

      int stepx = (int) (stepincrement * stepinterval/1000000000L);
      int rate = stepincrement;
      long stepy = calculateWaitingTime(rate);

      for(int i=0; i<warmupperiod_intervals; i++)
      {
        stepFunc.put(stepx, stepy);
        rate += stepincrement;
        stepx += (int) (stepincrement * stepinterval/1000000000L);
        stepy = calculateWaitingTime(rate);
        warmupops += stepx;
      }
    }

    //Update opcount property to reflect warmup (if feature enabled) + trace operation counts
    if(opcount>0)
      p.setProperty(Client.OPERATION_COUNT_PROPERTY, Long.toString(warmupops*threadcount + Math.min(lineCount, opcount)));
    else
      p.setProperty(Client.OPERATION_COUNT_PROPERTY, Long.toString(warmupops*threadcount + lineCount));

    super.init(p);
  }

  @Override
  public void doTransactionRead(DB db) {
    //keep this here in case we want to read keys from the trace file as well
    super.doTransactionRead(db);
  }

  @Override
  public long getDeadlineForTransaction(long startTimeNs, int opsdone, long targetOpsTickNs) {

    if ((opsdone >= warmupops) || (System.nanoTime() - startTimeNs >= warmupperiod_ns)) {
      //current_trace++;
      //System.out.println("current_warmup " + current_warm + " total_warmup " + warmupops*threadcount + " current_trace " + current_trace + " total_trace " + lineCount);

      //we are done warming up
      Long waitingTime = readTimestampFromFile(filegen);

      if(waitingTime == null)
        return -1;

//      if(waitingTime < (System.nanoTime()-startTimeNs)) {
//      this means that we are behind and didn't send the request in time
//      //TODO: Do we need to sound an alarm? Maybe not, since we can easily check by looking at the intended start time
//      }
      //System.out.println(Math.min(waitingTime, Math.max(opsdone * targetOpsTickNs, targetOpsTickNs)));
      return startTimeNs + warmupperiod_ns + waitingTime;
    }
    else {
      //current_warm++;
      //System.out.println("current_warmup " + current_warm + " total_warmup " + warmupops*threadcount + " current_trace " + current_trace + " total_trace " + lineCount);
      //still warming up
      //calculate the waiting time till the next operation
      long waitingTime = 0;
      int opcount = 0;
      for(Integer stepopcount: stepFunc.keySet())
      {
        opcount += stepopcount;
        if(opsdone > opcount) {
          waitingTime += stepopcount * stepFunc.get(stepopcount);
        }
        else {
          waitingTime += (opsdone-(opcount-stepopcount))* stepFunc.get(stepopcount);
          break;
        }
      }
      //System.out.println(waitingTime);
      return startTimeNs + waitingTime;
    }
  }

  /**
   * Reads and parses next line in the workload trace.
   * @throws UnsupportedOperationException
   */
  private static Long readTimestampFromFile(FileGenerator generator) throws UnsupportedOperationException {
    String line = generator.nextString();
    if(line == null) {
      return null;
    }
    line.replaceAll("\n", "");
    //System.out.println(Thread.currentThread().getId() + " T " + Long.parseLong(line));
    return Long.parseLong(line);
  }

  private static long calculateWaitingTime(long targetPerThread)
  {
    double targetperthread = ((double) targetPerThread);
    double targetperthreadperms = targetperthread / 1000.0;
    long targetOpsTickNs = (long) (1000000 / targetperthreadperms);

    return targetOpsTickNs;
  }
}

