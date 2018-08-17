#!/usr/bin/env Rscript

#Expansion function
expandInterval <- function(initial_nano, n, duration= 1000000000, constant=FALSE)
{
	#temp <- get(df, envir=envir)
	out = c(initial_nano)
	current_nano = initial_nano
	lambda = duration / n
	temp = c(initial_nano)

	if(n<=1)
	{
		return(out)
	}


	while(last(temp) < initial_nano + duration)
	{
		# divide duration by 1000 to avoid running into MAX_INTEGER problems with rpois
		if(constant)
		{
		    	interarrivals = rep.int(lambda/1000, (n))
		}
		else
		{
		    interarrivals = rpois((n), lambda/1000)
		}
		interarrivals = as.integer(interarrivals) *1000
		temp = tail(cumsum(c(last(temp),interarrivals)), -1)
		out = c(out, temp)
		
		#reduce n exponentially
		n = ceiling(n/2)
	}

	#remove any values that are higher than or equal to maximum duration
	out <- subset(out, out < initial_nano + duration)
	#assign(df, value=temp, envir=envir)
	return(out)
}

aggregateTrace <- function(files, src_dir, interval, offset, duration, rolling, window)
{
  sec_to_nanos <- 1000000000
  j <- interval * sec_to_nanos
  data <- list()
  count = 0
  for(file in files)
  {
	  count = count + 1
	  intended <- read.table(paste(src_dir, "/",file, sep=""), sep=" ", header=FALSE)
	  intended <- data.frame(time=intended[(intended$V1>=offset*sec_to_nanos),])
	  #intended$time <- intended$time - offset*sec_to_nanos
	  intended <- table((intended%/% j + 1) * j)
	  
	  intended_k <- min(c(floor(duration/interval), length(intended)))
	  
	  original <- data.frame(freq=as.vector(unname(intended))[1: intended_k],intervals=(as.numeric(names(intended))/1000000000)[1: intended_k])
	  
	  # Create a placeholder dataset, including all intervals, 0 at all other columns
	  data[[count]] <- data.frame(intervals = seq(0, max(original$intervals), interval),
	                    freq=0, check.names = FALSE)
	  
	  # write data from original dataset to placeholder dataset
	  data[[count]][data[[count]]$intervals %in% original$intervals,]$freq <- original$freq
	  
	  # convert back to req/s
	  data[[count]]$freq <- data[[count]]$freq/interval
	  
	  
	  if(rolling != "none")
	  {
	    data[[count]]$freq = rollapply(data[[count]]$freq, width=window, partial=TRUE, FUN=rolling)
	  }
  }
  return(data)
}

list.of.packages <- c("optparse", "zoo", "dplyr", "data.table")
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages, repos = "http://cran.us.r-project.org")

getFileName <- function(path)
{
  x <- unlist(strsplit(path, "/"))
  return(x[length(x)])
}

library("optparse")
library("zoo")
library(dplyr)
library(data.table)

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
  make_option(c("-vm", "--vms"), type="integer",
              default=5, help="max number of vms", metavar="number"),
  make_option(c("-r", "--rolling"), type="character",
              default="none", help="rolling function", metavar="character"),
  make_option(c("-er", "--enableRaw"), action="store_true",
              default=FALSE, help="Enable output of raw datapoints of scaled trace"),
  make_option(c("-c", "--capacities"), type="character",
              default="0,15000,30000,45000,55000,60000", help="Capacities for different cluster sizes (e.g. 0,15000,30000,45000)", metavar="character"),
  make_option(c("-p", "--prefix"), type="character",
              default="defaultprefix", help="prefix appended to output file", metavar="character"))

opt_parser = OptionParser(option_list=option_list)

opt = parse_args(opt_parser)
opt$capacities <- as.numeric(strsplit(opt$capacities, ",")[[1]])

if (is.null(opt$src_dir) || !dir.exists(opt$src_dir))
{
  print_help(opt_parser)
  stop("A trace directory must be supplied for intended timetamps", call.=FALSE)
}

files <- list.files(opt$src_dir, pattern = "\\.trace$")
total_inputs <- length(files)
max_freq <- 0
vm_duration <- 60 * 60 / opt$interval #expressed in terms of interval units
sec_to_nanos <- 1000000000

# (1) process traces to find out max frequency
traces <- aggregateTrace(files, opt$src_dir, opt$interval, opt$offset, opt$duration, opt$rolling, opt$window)

for(i in seq(1,total_inputs))
{
	if(max(traces[[i]]$freq) > max_freq)
	{
		max_freq = max(traces[[i]]$freq)
	}
}

# (2) compute the scaling factor
scalingFactor <- opt$capacities[opt$vms+1]/max_freq
print(paste("Origin Max Frequency(", max_freq, ") X Scaling Factor(", scalingFactor, ") = Scaled Max Frequency(", opt$capacities[opt$vms+1], ")", sep=""))
print(paste("SF:", scalingFactor))

if(opt$enableRaw)
{
# (3) scale the traces using default params
traces <- aggregateTrace(files, opt$src_dir, 1, 0, .Machine$integer.max, "none", 0)

scaledFiles <- c()
for(i in seq(1,length(traces)))
{
	trace <- traces[[i]]
	file <- files[[i]]
	
	outDir <- paste(opt$prefix, "_", file, "_scle_", scalingFactor, "_ycsb.strace", sep="")
	
	print(paste("Writing scaled trace to ", opt$dst_dir, "/", outDir, sep=""))
	scaledFiles <- c(scaledFiles, outDir)

	#apply expand function to every line
	out <- mapply(expandInterval, trace$intervals*sec_to_nanos, (trace$freq)*(scalingFactor), 1*sec_to_nanos, FALSE)
	write.table(unlist(out), paste(opt$dst_dir, outDir, sep=""), sep=" ", col.names = F, row.names = F)
}

# (4) Aggregate scaled traces and produce plots
traces <- aggregateTrace(scaledFiles, opt$dst_dir, opt$interval, opt$offset, opt$duration, opt$rolling, opt$window)

max_freq <- 0
min_freq <- .Machine$integer.max
max_interval <- 0

for(i in seq(1,total_inputs))
{
	intended_k <- min(c(floor(opt$duration/opt$interval), nrow(traces[[i]])))
	if(max(traces[[i]]$freq) > max_freq)
	{
		max_freq = max(traces[[i]]$freq)
	}
	
	if(min(traces[[i]]$freq) < min_freq)
	{
		min_freq = min(traces[[i]]$freq)
	}
	
	if(intended_k > max_interval)
	{
	    max_interval = intended_k
	}
}

colors <- palette(rainbow(total_inputs))
outputFile <- paste(opt$dst_dir, "/", opt$prefix, "_", "requests_sent_timeseries_", opt$offset, "_", opt$duration, "_",opt$rolling, "_", opt$window, ".png", sep="")
png(outputFile, width = 8, height = 6, units = 'in', res = 512)
plot(c(), c(), ylab="Number of transmissions", xlab="Time (s)", main=paste("Requests sent (", opt$interval, "s intervals)", sep=""), type="l", col = "blue", xlim=c(1+opt$offset, max_interval*opt$interval+opt$offset), ylim=c(min_freq, max_freq))
count <- 0
for(df in traces)
{
  count <- count + 1
  lines(df $intervals, df$freq, type = "l", col = colors[count])
}
legend("topleft", files, lty=rep(1, times=total_inputs), lwd=rep(2.5, times=total_inputs),col=colors)
dev.off()
}