#!/usr/bin/env Rscript

list.of.packages <- c("dplyr", "data.table", "optparse", "tictoc")
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages, repos = "http://cran.us.r-project.org")

library(dplyr)
library(data.table)
require(tictoc)
options(scipen = 999) #disable scientific notation

#sourceDir <- getSrcDirectory(function(dummy) {dummy})

#function for expanding trace
#FIXME: refactor and remove global variables
expand <- function(initial_nano, n, duration= 1000000000, constant=FALSE)
{
	#temp <- get(df, envir=envir)
	out <- vector(mode="numeric", length=0)
	current_nano = initial_nano
	lambda = duration / n

	while(current_nano < initial_nano + duration)
	{
	    out = c(out, current_nano)
	    if(constant)
	    	{
	    		interarrival = lambda
	    	}
	    	else
	    	{
	    		interarrival = rpois(1, lambda)
	    	}
		current_nano = current_nano + interarrival
	}
	#assign(df, value=temp, envir=envir)
	return(out)
}

#optimized expansion function
expand2 <- function(initial_nano, n, duration= 1000000000, constant=FALSE)
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

set.seed(124)

library("optparse")

option_list = list(
make_option(c("-f", "--src_file"), type="character",
default=NULL, help="dataset file name", metavar="character"),
make_option(c("-r", "--rate"), type="integer",
default=1000, help="target rate", metavar="number"),
make_option(c("-d", "--duration"), type="integer",
default=1, help="duration", metavar="number"),
make_option(c("-id", "--arrival_distr"), type="character",
default="poisson", help="Interarrival distribution"),
make_option(c("-vscale", "--vertical_scale"), type="integer",
default=1, help="Amplitude Scale"))

opt_parser = OptionParser(option_list=option_list)

opt = parse_args(opt_parser)

if (!is.null(opt$src_file)) {

	fileDir <- opt$src_file
	print(paste("Reading file from", fileDir))

	trace <- read.table(fileDir, sep=" ", header=TRUE)
	colnames(trace)[1] <- "index"
	colnames(trace)[2] <- "time_sec"
	colnames(trace)[3] <- "region_id"
	colnames(trace)[4] <- "relative_time_sec"
	colnames(trace)[5] <- "interarrival_sec"
	colnames(trace)[6] <- "1sec"
	colnames(trace)[7] <- "10sec"
	colnames(trace)[8] <- "1min"

	trace <- trace[,c("index", "relative_time_sec")]

	colnames(trace)[2] <- "relative_time_nanos"
	
	trace$relative_time_nanos <- trace$relative_time_nanos * 1000000000
	
	duration = opt$duration * 1000000000
	
	trace$relative_time_nanos <- cut(x= trace$relative_time_nanos, breaks=seq(from=floor(min(trace$relative_time_nanos)), to=ceiling(max(trace$relative_time_nanos)), by = duration), include.lowest=TRUE, right=FALSE, dig.lab=30)

	trace <- na.omit(trace)

	trace$relative_time_nanos <- as.numeric(substring(sapply(strsplit(as.character(trace$relative_time_nanos), split=","), head, 1),2))

	trace <- merge(trace %>% count(relative_time_nanos), trace, by="relative_time_nanos")

	trace <- subset(trace, !duplicated(relative_time_nanos))
	
	#Bygroup = tapply(trace$n, all$bins, mean)
	
} else {
	print("No trace file supplied. Generating synthetic trace..")

	req_count = opt$rate * opt$duration

	trace <- data.frame(relative_time_nanos=c(0), n=req_count)

	duration = opt$duration * 1000000000 #convert to ns

	fileDir <- paste("./", "samples/", "synthetic_trace_", opt$rate, "_", opt$duration, "_", opt$arrival_distr, ".data", sep="")
}

print("Generating poisson process interarrivals and creating ycsb trace")

tic()
#apply expand function to every line
out <- mapply(expand2, trace$relative_time_nanos, (trace$n)*(opt$vertical_scale), duration, opt$arrival_distr == "constant")

exectime <- toc()
exectime <- exectime$toc - exectime$tic
print(paste("Finished execution in: ", exectime))

outDir <- paste(fileDir, "_scle_", opt$vertical_scale, "_ycsb.trace", sep="")
print(paste("Saving output trace to", outDir))

write.table(unlist(out), outDir, sep=" ", col.names = F, row.names = F)


#perform some additional analyses
# k <- 500
# x <- unlist(out)
# timeseries <- table((x%/% 1000000000 + 1) * 1000000000)
# timeseries_df <- data.frame(freq=as.vector(unname(timeseries))[1:k],intervals=(as.numeric(names(timeseries))/1000000000)[1:k])

# plot(timeseries_df$interval, timeseries_df$freq, ylab="Number of transmissions", xlab="Time (s)", main="Requests sent (1s intervals)", type="l", col = "blue", ylim=c(0,20), xlim=c(0, k))

# fileDir2 <- paste("../", "temp2", sep="")

# ycsb_run <- read.table(fileDir2, sep=" ", header=FALSE)
# colnames(ycsb_run)[1] <- "thread_id"
# colnames(ycsb_run)[2] <- "R"
# colnames(ycsb_run)[3] <- "time"

# ycsb <- table((ycsb_run$time %/% 1000000000 + 1) * 1000000000)
# ycsb_df <- data.frame(freq=as.vector(unname(ycsb))[1:k],intervals=(as.numeric(names(ycsb))/1000000000)[1:k])
# lines(ycsb_df $interval, ycsb_df $freq, type = "l", col = "red")
# legend("topleft", c("Intended","Actual (non-spinning)"),lty=c(1,1), lwd=c(2.5,2.5),col=c("blue","red"))

# df_sp <- data.frame(threads=c(2,8,16), actual=c(1695.0, 2151.0, 3329.0), intended=c(2731.667, 2299.0, 9343.0))
# df_sp$error <- df_sp$intended - df_sp$actual
# df_nsp <- data.frame(threads=c(2,8,16), actual=c(2006.0, 1917.0, 1906.0), intended=c(4915.0, 5279.0, 5195.0))
# df_nsp$error <- df_nsp$intended - df_nsp$actual

# counts <- table(df_sp$, df_sp$threads)
# barplot(counts, main="Car Distribution by Gears and VS",
  # xlab="Number of Gears", col=c("darkblue","red"),
  # legend = rownames(counts), beside=TRUE)

# barplot(t(matrix(c(df_sp$error, df_nsp$error),nr=3)), beside=T, xlab="Number of threads",
        # col=c("coral","lightblue"), ylab="Median error (us)", ylim=c(0,8000),main="Error Margin for Workload Generation",
        # names.arg=df_sp$threads)
# legend("topright", c("Spinning","Sleeping"), fill=c("coral","lightblue"),
       # bty="n")

# #calculate percentage difference
# diff = abs(as.vector(unname(timeseries))[1:k] - as.vector(unname(ycsb))[1:k])/as.vector(unname(timeseries))[1:k] * 100
