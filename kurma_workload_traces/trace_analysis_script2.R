#!/usr/bin/env Rscript
options(error = quote({
  dump.frames(to.file=T, dumpto='last.dump')
  load('last.dump.rda')
  print(last.dump)
  q()
}))

list.of.packages <- c("optparse", "zoo")
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages, repos = "http://cran.us.r-project.org")

getFileName <- function(path)
{
  x <- unlist(strsplit(path, "/"))
  return(x[length(x)])
}

library("optparse")
library("zoo")

option_list = list(
  make_option(c("-sd", "--src_dir"), type="character",
              default=NULL, help="src directory for trace files", metavar="character"),
  make_option(c("-dd", "--dst_dir"), type="character",
              default=NULL, help="destination directory for outputs", metavar="character"),
  make_option(c("-o", "--offset"), type="integer",
              default=0, help="defines the time at which we will begin processing trace (in sec)", metavar="number"),
  make_option(c("-d", "--duration"), type="integer",
              default=.Machine$integer.max, help="duration for which trace will be processed (in sec)", metavar="number"),
  make_option(c("-i", "--interval"), type="integer",
              default=1, help="the interval covered by datapoints (in sec)", metavar="number"),
  make_option(c("-w", "--window"), type="integer",
              default=2, help="window in interval units", metavar="number"),
  make_option(c("-dc", "--dc"), type="integer",
              default=3, help="number of datacenters", metavar="number"),
  make_option(c("-r", "--rolling"), type="character",
              default="none", help="rolling function", metavar="character"),
  make_option(c("-ss", "--scalingstrategy"), type="character",
              default="localslo", help="Set the strategy for scaling VMs (either localslo', 'slo', or 'redirection')", metavar="character"),
  make_option(c("-c", "--capacities"), type="character",
              default="0,15000,30000,45000,55000,60000", help="Capacities for different cluster sizes (e.g. 0,15000,30000,45000)", metavar="character"),
  make_option(c("-pslo", "--path2_slo_curves_fzn"), type="character",
              default="/home/kirillb/projects/lx3/sources/nc_ycsb/models/kurma/slo_curves.amz/data_amz_scaled_1to40vms.dzn", help="Path to SLO curves", metavar="character"),
  make_option(c("-pmodel", "--path2_model_mzn"), type="character",
              default="/home/kirillb/projects/lx3/sources/nc_ycsb/models/kurma/multi_3d.mzn", help="Path to model definition file", metavar="character"),
  make_option(c("-s", "--scalingfactor"), type="integer",
              default=0, help="the scaling factor for the input traces", metavar="number"),
  make_option(c("-vd", "--vmduration"), type="integer",
              default=60, help="minimum billing period for VMs", metavar="number"),
  make_option(c("-um", "--useModel"), action="store_true",
              default=FALSE, help="Use Kurma's model to compute # of VMs that need to be provisioned along the timeseries"),
  make_option(c("-de", "--debug"), action="store_true",
              default=FALSE, help="Enable debug mode (outputs results of system calls)"),
  make_option(c("-md", "--model_dir"), type="character",
              default="/home/kirillb/projects/lx3/sources/nc_ycsb/models/", help="src directory for model script file", metavar="character"),
  make_option(c("-p", "--prefix"), type="character",
              default="defaultprefix", help="prefix appended to output file", metavar="character"))

opt_parser = OptionParser(option_list=option_list)

opt = parse_args(opt_parser)
opt$capacities <- as.numeric(strsplit(opt$capacities, ",")[[1]])

if (is.null(opt$src_dir) || !dir.exists(opt$src_dir))
{
  print_help(opt_parser)
  stop("A directory must be provided for the input trace files.", call.=FALSE)
}

if (!(opt$scalingstrategy == "slo" | opt$scalingstrategy == "redirection" | opt$scalingstrategy == "localslo"))
{
  print_help(opt_parser)
  stop("Invalid scaling strategy. Either 'localslo', 'slo', or 'redirection' is allowed.", call.=FALSE)
}

if(opt$scalingfactor == 0)
{
  files <- list.files(opt$src_dir, pattern = "\\.strace$")
} else
{
  files <- list.files(opt$src_dir, pattern = "\\.trace$")
}

files <- files[1:opt$dc]
total_inputs <- max(length(files), opt$dc)
data <- list()
count = 0
max_freq <- 0
min_freq <- .Machine$integer.max
max_interval <- 0
sec_to_nanos <- 1000000000
j <- opt$interval*sec_to_nanos
#vm_duration <- 60 * 60 / opt$interval #expressed in terms of interval units
vm_duration <- 60 * opt$vmduration / opt$interval
model_name = tail(strsplit(opt$path2_model_mzn, "/")[[1]], n=1)

#read and parse traces
for(file in files)
{
  count = count + 1
  intended <- read.table(paste(opt$src_dir, "/",file, sep=""), sep=" ", header=FALSE)
  intended <- data.frame(time=intended[(intended$V1>=opt$offset*sec_to_nanos),])
  #intended$time <- intended$time - opt$offset*sec_to_nanos
  intended <- table((intended%/% j + 1) * j)
  
  intended_k <- min(c(floor(opt$duration/opt$interval), length(intended)))
  
  original <- data.frame(freq=as.vector(unname(intended))[1: intended_k],intervals=(as.numeric(names(intended))/1000000000)[1: intended_k])
  
  # Create a placeholder dataset, including all intervals, 0 at all other columns
  data[[count]] <- data.frame(intervals = seq(0, max(original$intervals), opt$interval),
                              freq=0, check.names = FALSE)
  
  # write data from original dataset to placeholder dataset
  data[[count]][data[[count]]$intervals %in% original$intervals,]$freq <- original$freq
  
  # convert back to req/s
  data[[count]]$freq <- data[[count]]$freq/opt$interval
  
  # scale trace if scalingfactor > 0
  if(opt$scalingfactor > 0)
  {
    data[[count]]$freq <- data[[count]]$freq * opt$scalingfactor
  }
  
  if(opt$rolling != "none")
  {
    data[[count]]$freq = rollapply(data[[count]]$freq, width=opt$window, partial=TRUE, FUN=opt$rolling)
  }
  
  if(nrow(data[[count]]) > max_interval)
  {
    max_interval = nrow(data[[count]])
  }
  
  current_freq_min <- min(data[[count]]$freq)
  current_freq_max <- max(data[[count]]$freq)
  if(current_freq_min < min_freq)
  {
    min_freq <- current_freq_min
  }
  if(current_freq_max > max_freq)
  {
    max_freq <- current_freq_max
  }
}

print("MAX INTERVAL")
print(max_interval)
#Find VM allocations for shared-nothing scheme
max_vm_hours <- 0
count <- 0
for(df in data)
{
  count <- count + 1
  df$vm_els <- rep(0, nrow(df))
  df$rate_els <- rep(0, nrow(df))
  currentVMs <- 0
  for(i in rownames(df))
  {
    freq <- df[i, "freq"]
    #print("-----------")
    #print(length(currentVMs)+1)
    #print(freq)
    #print("-----------")
    while(freq > opt$capacities[length(currentVMs)+1])
    {
      #scale up
      print(freq)
      print(opt$capacities)
      print(length(currentVMs)+1)
      currentVMs <- c(currentVMs, vm_duration)
      max_vm_hours <- max_vm_hours + 1
    }
    
    #reduce duration by 1
    currentVMs <- currentVMs - 1
    
    #add point to dataframe
    df[i, "vm_els"] <- length(currentVMs)
    
    df[i, "rate_els"] <- opt$capacities[length(currentVMs)+1]
    
    #remove VMs after they've expended their alotted time
    currentVMs <- currentVMs[currentVMs > 0]
  }
  
  data[[count]] <- df
  
  #produce plot
  colors <- palette(rainbow(2))
  outputFile <- paste(opt$dst_dir, "/", opt$prefix, "_", "boxy_plots_", files[[count]], opt$offset, "_", opt$duration, "_",opt$rolling, "_", opt$window, ".png", sep="")
  png(outputFile, width = 8, height = 6, units = 'in', res = 512)
  plot(c(), c(), ylab="Sending rate / Capacity (reqs/s)", xlab="Time (s)", main=paste("Requests sent (", opt$interval, "s intervals)", sep=""), type="l", col = "blue", xlim=c(min(df$intervals), max(df$intervals)), ylim=c(min(df$freq), max(df$rate_els)))
  
  lines(df $intervals, df$freq, type = "l", col = colors[1])
  lines(df $intervals, df$rate_els, type = "l", col = colors[2])
  legend("topleft", c("Sending rate", "VM Capacity"), lty=rep(1, times=2), lwd=rep(2.5, times=2),col=colors)
  dev.off()
}

#Aggregate curves for all-shared scheme
count <- 0
uberDF <- data.frame(intervals = seq(0, max_interval*opt$interval, opt$interval),
                     freq=0, vm_els=0, vm_kurma=0, redir_kurma=0, rates="", servers="", check.names = FALSE, stringsAsFactors=FALSE)

for(df in data)
{
  uberDF[1:nrow(df),]$vm_els <- uberDF[1:nrow(df),]$vm_els + df$vm_els
  uberDF[1:nrow(df),]$freq <- uberDF[1:nrow(df),]$freq + df$freq
  
  if(opt$debug)
  {
    #generate debug output
    uberDF[1:nrow(df),]$rates <- paste(uberDF[1:nrow(df),]$rates, df$freq)
    print(head(uberDF[1:nrow(df),]$rates))
    print(head(df$freq))
    uberDF[1:nrow(df),]$servers <- paste(uberDF[1:nrow(df),]$servers, df$vm_els)
  }
}

#print debug output
if(opt$debug)
{
  debugFile <- paste(opt$dst_dir, "/", opt$prefix, "_", "sharedNothingDebug_", opt$offset, "_", opt$duration, "_",opt$rolling, "_", opt$window, sep="")
  write.csv(uberDF[,c("rates","servers")], debugFile, row.names = F, col.names = F)
}


uberDF $vm_agg_els <- rep(0, nrow(uberDF))
currentVMs <- list()

#initialize list with empty vectors (is there a more efficient way of expressing this in R?)
for(i in seq(1,opt$dc))
{
  currentVMs[[i]] <- vector(mode="numeric", length=0)
}

#Find VM allocations for all-shared scheme
min_vm_hours <- 0
currentCapacity <- 0

debugMatrix = matrix(0, ncol = 4, nrow = 0)

for(i in rownames(uberDF))
{
  freq <- uberDF[i, "freq"]
  #print(tail(uberDF))
  #print(freq)
  while(freq > currentCapacity)
  {	
    minIndex = 1
    minValue = .Machine$integer.max
    for(v in seq(1,opt$dc))
    {
      #we choose to scale the cluster with the minimum number of VMs due to the non-linearity of the opcurves (i.e. we try to minimize the effect of diminishing returns)
      if(length(currentVMs[[v]])<minValue)
      {
        minIndex  = v
        minValue = length(currentVMs[[v]])
      }
    }
    
    #scale up
    currentVMs[[minIndex]] <- c(currentVMs[[minIndex]], vm_duration)
    
    min_vm_hours <- min_vm_hours + 1
    
    currentCapacity <- 0
    
    #calculate new capacity
    for(v in seq(1,opt$dc))
    {
      currentCapacity <- currentCapacity + opt$capacities[length(currentVMs[[v]])+1]
    }
  }
  
  totalVMs <- 0
  #reduce duration by 1
  for(v in seq(1,opt$dc))
  {
    currentVMs[[v]] <- currentVMs[[v]] - 1
    totalVMs <- totalVMs + length(currentVMs[[v]])
  }
  
  #add point to dataframe
  uberDF[i, "vm_agg_els"] <- totalVMs
 
  #remove VMs after they've expended their alotted time
  for(v in seq(1,opt$dc))
  {
    currentVMs[[v]] <- currentVMs[[v]][currentVMs[[v]] > 0]
  }
  
  currentCapacity <- 0
  
  servers = ""
  
  #calculate new capacity
  for(v in seq(1,opt$dc))
  {
    currentCapacity <- currentCapacity + opt$capacities[length(currentVMs[[v]])+1]
    servers <- paste(servers, toString(length(currentVMs[[v]])))
  }
  
  if(opt$debug)
  {
    debugVector = c(i, freq, servers, paste(currentVMs,collapse=" "))
    debugMatrix <- rbind(debugMatrix, debugVector)
  }    
}

#print debug output
if(opt$debug)
{
  
  debugFile <- paste(opt$dst_dir, "/", opt$prefix, "_", "allSharedDebug_", opt$offset, "_", opt$duration, "_",opt$rolling, "_", opt$window, sep="")
  write.csv(debugMatrix, debugFile, row.names = F, col.names = F)
}

#find VM allocations for model scheme
if(opt$useModel)
{
  debugMatrix = matrix(0, ncol = 4, nrow = 0)
  
  kurma_vm_hours <- 0
  
  kurma_redir <- 0
  
  #estimate VM allocations using Kurma's model
  #initialize list with empty vectors (is there a more efficient way of expressing this in R?)
  for(i in seq(1,opt$dc))
  {
    currentVMs[[i]] <- vector(mode="numeric", length=0)
  }
  
  for(i in rownames(uberDF))
  {
    
    ratesString = ""
    rates = vector(mode="numeric", length=0)
    servers = ""
    count = 0
    
    for(df in data)
    {
      count = count + 1
      #print(i)
      #print(nrow(df))
      if(is.na(df[i, "freq"]))
      {
        r = 0
      } else {
        r = df[i, "freq"]
      }
      rates <- c(rates,r)
      
      #if(round(r/100) > 0 && length(currentVMs[[count]]) == 0)
      #{
        #scale up (to avoid issues with kirill's script)
        #print(r)
      #  currentVMs[[count]] <- c(currentVMs[[count]], vm_duration)
      #  kurma_vm_hours <- kurma_vm_hours + 1
      #}
      #print(currentVMs)
      #print(count)
      #print(opt$dc)
      #print(length(data))
      #print(total_inputs)
      #print(files)
      servers <- paste(servers, toString(length(currentVMs[[count]])))
    }
 
    ratesString = paste(round(rates/100), collapse=" ")
print("==========================================")
print(i)
    if(i==607)
{
print("Initial stats")
print(ratesString)
print(servers)
}
    #print("--------------------------------")
    #print(ratesString)
    #print(servers)
    #print("--------------------------------")
    if(ratesString == "0 0 0")
    {
      #set slo to 0 to avoid issues with kirill's script
      if(opt$scalingstrategy == "localslo")
      {
        slo = c(0,0,0)
      } else {
        slo = 0		
      }
      redir = 0
    } else {
      cmd = paste("sudo env PYTHONPATH=$PYTHONPATH ", opt$model_dir, "model_executor.py --clients_rates ", ratesString, " --server_count ", servers, " --path2_slo_curves_fzn ", opt$path2_slo_curves_fzn, " --path2_model_mzn ", opt$path2_model_mzn, sep="")
      #print("Outputting cmd")
      #print(cmd)
      out = system(cmd, intern=TRUE)
      if(opt$debug)
      {
        print(cmd)
        print(out)
      }
      #cmd2 = paste("echo ",  slo, " | grep -oP '(?<=SLO:  )[0-9]+.[0-9]+'")
      if(opt$scalingstrategy == "localslo")
      {
        slo = vector(mode="numeric", length=0)
        for(v in seq(1,opt$dc))
        {
	  #we also handle the case for rates!=1 as model_executor.py for some reason fails to produce the failure rates in such cases
          if(rates[v] >150)
          {
            matchString = paste("dc", v, "_failure_rate", sep="")
            sloIndex = pmatch(matchString, out)
            temp = strsplit(out[sloIndex], "=")[[1]][2]
            temp = substr(temp, 1, nchar(temp)-1)
            #print(slo)
            temp = as.numeric(temp)
          } else {
            temp = 0
          }
            if(!is.na(pmatch("=====UNSATISFIABLE=====", out)))
            {
                #temp = NA
print("YEEESfdsfkjdsklfdjskfldj")
            }
            else
                {
                        print("NOOOOOOOOOOO")
                }
          slo = c(slo, temp)
        }
        condition = !any(is.na(slo))
      } else {
        sloIndex = pmatch("SLO", out)
        slo = strsplit(out[sloIndex], ":")[[1]][2]
        #print(slo)
        slo = as.numeric(slo)
            if(!is.na(pmatch("=====UNSATISFIABLE=====", out)))
            {
                #slo = NA
		print("YEEESfdsfkjdsklfdjskfldj")
            }
            else
                {
                        print("NOOOOOOOOOOO")
                }
        condition = !is.na(slo)
      }
      if(condition)
      {
        redirIndex = pmatch("rates_matrix", out)	    		
        m <- regexpr('\\[(.*?)\\]', out[redirIndex], perl=TRUE)
        redir <- regmatches(out[12], m)
        print(redir)
        redir <- gsub("\\[|\\]", "", redir)
        redir <- as.numeric(strsplit(redir, ",")[[1]])
        redir <- matrix(redir,ncol=total_inputs)*100
        redir <- sum(redir[row(redir) != (col(redir))])
      }
    }
    
    if(opt$scalingstrategy == "localslo")
    {
      #we don't know which dc to scale, choose the one with the highest excess load
      while(any(is.na(slo)))
      {
        maxRateDeltaIndex = -1
        maxRateDelta = -.Machine$integer.max
        
        for(v in seq(1,opt$dc))
        {
	  #print("-----------------")
	  #print(v)
	  #print(length(currentVMs[[v]])+1)
	  #print(opt$capacities[length(currentVMs[[v]])+1])
	  #print(maxRateDelta)
	  #print("-----------------")
          if((rates[v]-opt$capacities[length(currentVMs[[v]])+1])>maxRateDelta)
          {
            maxRateDelta = rates[v]-opt$capacities[length(currentVMs[[v]])+1]
            maxRateDeltaIndex = v
          }
        }
        
        #scale dc with maxRateDeltai
        #print("scaling")
        #print("before")
	#print(currentVMs)
        currentVMs[[maxRateDeltaIndex]] <- c(currentVMs[[maxRateDeltaIndex]], vm_duration)
        kurma_vm_hours <- kurma_vm_hours + 1	
        #print("scaling")
	#print("after")
	#print(currentVMs)

        servers = ""
        for(v in seq(1,opt$dc))
        {
          servers <- paste(servers, toString(length(currentVMs[[v]])))
        }
        
        #recalculate slos
        cmd = paste("sudo env PYTHONPATH=$PYTHONPATH ", opt$model_dir, "model_executor.py --clients_rates ", ratesString, " --server_count ", servers, " --path2_slo_curves_fzn ", opt$path2_slo_curves_fzn, " --path2_model_mzn ", opt$path2_model_mzn, sep="")
        out = system(cmd, intern=TRUE)
        if(opt$debug)
        {
          print(cmd)
	  print(out)
        }
        for(v in seq(1,opt$dc))
        {
          if(rates[v] > 150)
          {
            matchString = paste("dc", v, "_failure_rate", sep="")
            sloIndex = pmatch(matchString, out)
            temp = strsplit(out[sloIndex], "=")[[1]][2]
            temp = substr(temp, 1, nchar(temp)-1)
            #print(slo)
            temp = as.numeric(temp)	
          } else {
            temp = 0
          }
            if(!is.na(pmatch("=====UNSATISFIABLE=====", out)))
            {
                #temp = NA
print("YEEESfdsfkjdsklfdjskfldj")
            }
            else
                {
                        print("NOOOOOOOOOOO")
                }
          slo[v] = temp
        }
        if(!any(is.na(slo)))
        {
          redirIndex = pmatch("rates_matrix", out)	    		
          m <- regexpr('\\[(.*?)\\]', out[redirIndex], perl=TRUE)
          redir <- regmatches(out[12], m)
          print(redir)
          redir <- gsub("\\[|\\]", "", redir)
          redir <- as.numeric(strsplit(redir, ",")[[1]])
          redir <- matrix(redir,ncol=total_inputs)*100
          redir <- sum(redir[row(redir) != (col(redir))])
        }
      }
      
      #we do know which dc to scale, scale DCs for which SLO violations > 5%
      while(any(slo > 5))
      {
	#print("scaling - due to slo > 5")
	#print("before")
	#print(currentVMs)
        #servers = ""
        #for(v in seq(1,opt$dc))
        #{
        #  if(slo[v] > 5)
        #  {
        #    currentVMs[[v]] <- c(currentVMs[[v]], vm_duration)
        #    kurma_vm_hours <- kurma_vm_hours + 1	
        #  }
        #  servers <- paste(servers, toString(length(currentVMs[[v]])))
        #}

	#print("after")
	#print(currentVMs)
        
        #recalculate slos
        maxRateDeltaIndex = -1
        maxRateDelta = -.Machine$integer.max

        for(v in seq(1,opt$dc))
        {
          #print("-----------------")
          #print(v)
          #print(length(currentVMs[[v]])+1)
          #print(opt$capacities[length(currentVMs[[v]])+1])
          #print(maxRateDelta)
          #print("-----------------")
          if((rates[v]-opt$capacities[length(currentVMs[[v]])+1])>maxRateDelta)
          {
            maxRateDelta = rates[v]-opt$capacities[length(currentVMs[[v]])+1]
            maxRateDeltaIndex = v
          }
        }

        #scale dc with maxRateDeltai
        #print("scaling")
        #print("before")
        #print(currentVMs)
        currentVMs[[maxRateDeltaIndex]] <- c(currentVMs[[maxRateDeltaIndex]], vm_duration)
        kurma_vm_hours <- kurma_vm_hours + 1
        #print("scaling")
        #print("after")
        #print(currentVMs)

        servers = ""
        for(v in seq(1,opt$dc))
        {
          servers <- paste(servers, toString(length(currentVMs[[v]])))
        }

        cmd = paste("sudo env PYTHONPATH=$PYTHONPATH ", opt$model_dir, "model_executor.py --clients_rates ", ratesString, " --server_count ", servers, " --path2_slo_curves_fzn ", opt$path2_slo_curves_fzn, " --path2_model_mzn ", opt$path2_model_mzn, sep="")
        out = system(cmd, intern=TRUE)
        if(opt$debug)
        {
          print(cmd)
        }
        for(v in seq(1,opt$dc))
        {
          if(rates[v] > 150)
          {
            matchString = paste("dc", v, "_failure_rate", sep="")
            sloIndex = pmatch(matchString, out)
            temp = strsplit(out[sloIndex], "=")[[1]][2]
            temp = substr(temp, 1, nchar(temp)-1)
            #print(slo)
            temp = as.numeric(temp)
          } else {
            temp = 0
          }
            if(!is.na(pmatch("=====UNSATISFIABLE=====", out)))
            {
                #temp = NA
print("YEEESfdsfkjdsklfdjskfldj")
            }
            else
                {
                        print("NOOOOOOOOOOO")
                }
          slo[v] = temp
        }
        if(!any(is.na(slo)))
        {
          redirIndex = pmatch("rates_matrix", out)	    		
          m <- regexpr('\\[(.*?)\\]', out[redirIndex], perl=TRUE)
          redir <- regmatches(out[12], m)
          print(redir)
          redir <- gsub("\\[|\\]", "", redir)
          redir <- as.numeric(strsplit(redir, ",")[[1]])
          redir <- matrix(redir,ncol=total_inputs)*100
          redir <- sum(redir[row(redir) != (col(redir))])
        }
      }
    } else
    {
      while(is.na(slo) | slo > 5)
      {
        #scale up as long as we're below 5% (or model is unsatisfiable)
        minSLO = .Machine$integer.max
        minRedir = .Machine$integer.max
        minIndex = -1
        maxRateDeltaIndex = -1
        maxRateDelta = -.Machine$integer.max
        
        for(i in seq(1,total_inputs))
        {
          #print("Start")
          #print(i)
          #print(rates[i])
          #print(length(currentVMs[[i]])+1)
          #print(opt$capacities[length(currentVMs[[i]])+1])
          #print(length(currentVMs[[i]])+1)
          #print(maxRateDelta)
          #print("End")
          if((rates[i]-opt$capacities[length(currentVMs[[i]])+1])>maxRateDelta)
          {
            maxRateDelta = rates[i]-opt$capacities[length(currentVMs[[i]])+1]
            maxRateDeltaIndex = i
          }
        }
        
        for(j in seq(1,opt$dc))
        {
          servers = ""
          for(k in seq(1,opt$dc))
          {
            if(j == k)
            {
              servers <- paste(servers, toString(length(currentVMs[[k]]) + 1))
            }
            else
            {
              servers <- paste(servers, toString(length(currentVMs[[k]])))
            }
          }
          cmd = paste("sudo env PYTHONPATH=$PYTHONPATH ", opt$model_dir, "model_executor.py --clients_rates ", ratesString, " --server_count ", servers, " --path2_slo_curves_fzn ", opt$path2_slo_curves_fzn, " --path2_model_mzn ", opt$path2_model_mzn, sep="")
          out = system(cmd, intern=TRUE)
          if(opt$debug)
          {
            print(cmd)
            #print(out)
          }
          sloIndex = pmatch("SLO", out)
          newSLO = strsplit(out[sloIndex], ":")[[1]][2]
          newSLO = as.numeric(newSLO)
            if(!is.na(pmatch("=====UNSATISFIABLE=====", out)))
            {
                #newSLO = NA
print("YEEESfdsfkjdsklfdjskfldj")
            }
            else
                {
                        print("NOOOOOOOOOOO")
                }
          if(is.na(newSLO))
          {
            #skip to next value (we probably exceeded our max number of servers)
            next
          } else {
            redirIndex = pmatch("rates_matrix", out)
            m <- regexpr('\\[(.*?)\\]', out[redirIndex], perl=TRUE)             
            newRedir <- regmatches(out[redirIndex], m)
            print(newRedir)
            newRedir <- gsub("\\[|\\]", "", newRedir)
            newRedir <- as.numeric(strsplit(newRedir, ",")[[1]])
            newRedir <- matrix(newRedir,ncol=total_inputs) * 100
            newRedir <- sum(newRedir[row(newRedir) != (col(newRedir))])
          }
          if(opt$scalingstrategy == "slo")
          {
            if(newSLO < minSLO)
            {
              minSLO = newSLO
              minIndex = j
              redir = newRedir
            }
          }
          else
          {
            if(newRedir < minRedir)
            {
              minRedir = newRedir
              minIndex = j
              redir = newRedir
            }
          }
        }
        
        #if model is unsatisfiable in all cases, then add a VM to the DC with the highest excess load
        if(minIndex == -1)
        {
          minIndex = maxRateDeltaIndex
        }
        
        #add VM
        currentVMs[[minIndex]] <- c(currentVMs[[minIndex]], vm_duration)
        kurma_vm_hours <- kurma_vm_hours + 1	
        
        slo = minSLO
        #print(paste("New capacity: ", currentCapacity, " Rates:", rates, " Min SLO: ", minSLO))
      }
    }
    
    if(opt$debug)
    {
      debugVector = c(i, ratesString, servers, paste(currentVMs,collapse=" "))
      debugMatrix <- rbind(debugMatrix, debugVector)
    }
    
    totalVMs <- 0
    
    #reduce duration by 1
    for(v in seq(1,opt$dc))
    {
      currentVMs[[v]] <- currentVMs[[v]] - 1
      totalVMs <- totalVMs + length(currentVMs[[v]])
    }
    
    #add point to dataframe
    uberDF[i, "vm_kurma"] <- totalVMs
    uberDF[i, "redir_kurma"] <- redir * opt$interval
    
    #aggregate redirections
    kurma_redir <- kurma_redir + redir * opt$interval
    
    #remove VMs after they've expended their alotted time
    for(v in seq(1,opt$dc))
    {
      currentVMs[[v]] <- currentVMs[[v]][currentVMs[[v]] > 0]
    }
    
    currentCapacity <- 0
    
    #calculate new capacity
    for(v in seq(1,opt$dc))
    {
      currentCapacity <- currentCapacity + opt$capacities[length(currentVMs[[v]])+1]
    }	
  }
  #print("END CHECK")
  
  if(opt$debug)
  {
    
    debugFile <- paste(opt$dst_dir, "/", opt$prefix, "_", "modelDebug_", model_name, "_", opt$scalingstrategy, "_", opt$offset, "_", opt$duration, "_",opt$rolling, "_", opt$window, sep="")
    write.csv(debugMatrix, debugFile, row.names = F, col.names = F)
  }
}

#produce plot
colors <- palette(rainbow(3))

print(max)
outputFile <- paste(opt$dst_dir, "/", opt$prefix, "_", "aggregate_boxy_plots_", model_name, "_", opt$scalingstrategy, "_", opt$offset, "_", opt$duration, "_",opt$rolling, "_", opt$window, ".png", sep="")
png(outputFile, width = 8, height = 6, units = 'in', res = 512)
plot(c(), c(), ylab="Total # of VMs", xlab="Time (s)", main=paste("VM Count (", opt$interval, "s intervals) - Maximum cost reduction = ", round((max_vm_hours-min_vm_hours)/max_vm_hours*100), " %", sep=""), type="l", col = "blue", xlim=c(min(uberDF $intervals), max(uberDF $intervals)), ylim=c(0, max(uberDF $vm_els)))
lines(uberDF $intervals, uberDF$vm_els, type = "l", col = "red")
#lines(data[[1]] $intervals, data[[1]]$vm_els, type = "l", col = "green")
#lines(data[[2]] $intervals, data[[2]]$vm_els, type = "l", col = "black")
#lines(data[[3]] $intervals, data[[3]]$vm_els, type = "l", col = "blue")
#lines(data[[4]] $intervals, data[[4]]$vm_els, type = "l", col = "orange")
lines(uberDF $intervals, uberDF$vm_agg_els, type = "l", col = "green")
if(opt$useModel)
{
  lines(uberDF $intervals, uberDF$vm_kurma, type = "l", col = "black")
  legend("topleft", c(paste("Upper bound (no redirection) - VM hours =", max_vm_hours), paste("Lower bound (all shared) - VM hours =", min_vm_hours), paste("Kurma - VM hours =", kurma_vm_hours)), lty=rep(1, times=3), lwd=rep(2.5, times=3),col=c("red","green","black"))
} else {
  legend("topleft", c(paste("Upper bound (no redirection) - VM hours =", max_vm_hours), paste("Lower bound (all shared) - VM hours =", min_vm_hours)), lty=rep(1, times=2), lwd=rep(2.5, times=2),col=c("red","green"))	
}
dev.off()


outputFile <- paste(opt$dst_dir, "/", opt$prefix, "_", "cost_savings_", model_name, "_", opt$scalingstrategy, "_",  opt$offset, "_", opt$duration, "_",opt$rolling, "_", opt$window, ".csv", sep="")
if(opt$useModel)
{
  kurma_vm_hours_name = paste("kurma_", model_name, "_", opt$scalingstrategy, "_vm_hours", sep="")
  assign(paste(kurma_vm_hours_name), c(kurma_vm_hours))
  kurma_savings_name = paste("kurma_", model_name, "_", opt$scalingstrategy, "_kurma_savings", sep="")
  assign(paste(kurma_savings_name), c(round((max_vm_hours-kurma_vm_hours)/max_vm_hours*100)))
  kurma_redir_name = paste("kurma_", model_name, "_", opt$scalingstrategy, "_kurma_redir", sep="")
  assign(paste(kurma_redir_name), c(kurma_redir))
  write.csv(data.frame(max_vm_hours=c(max_vm_hours), min_vm_hours=c(min_vm_hours), mget(kurma_vm_hours_name), max_savings=c(round((max_vm_hours-min_vm_hours)/max_vm_hours*100)), mget(kurma_savings_name), mget(kurma_redir_name)), outputFile, col.names = T, row.names = F)
} else {
  write.csv(data.frame(max_vm_hours=c(max_vm_hours), min_vm_hours=c(min_vm_hours), max_savings=c(round((max_vm_hours-min_vm_hours)/max_vm_hours*100))), outputFile, col.names = T, row.names = F)	
}
