#!/usr/bin/env Rscript
library("optparse")

sourceDir <- getSrcDirectory(function(dummy) {dummy})
#sourceDir <- "."

option_list = list( make_option(c("-s", "--scale_factor"), type="numeric",
default=0.0025, help="Scaling factor", metavar="numeric"),
make_option(c("-f", "--src_file"), type="character",
default="samples/unix_ts_22_1.out_reg1.data_ycsb.data",
help="dataset file name", metavar="character"),
make_option(c("-r", "--repetition"), type="integer",
default=10, help="Scaling factor", metavar="integer"))

opt_parser = OptionParser(option_list=option_list)
 
opt = parse_args(opt_parser)

if (is.null(opt$src_file))
{
	print_help(opt_parser)
	stop("An input YCSB trace file must be supplied", call.=FALSE)
}

inputDir <- paste(sourceDir, "./", opt$src_file, sep="")
print(paste("Reading file from", inputDir))

trace <- read.table(inputDir, sep=" ", header=FALSE)
colnames(trace)[1] <- "timestamp_ns"

trace$interarrival_ns <- round(c(0, diff(trace$timestamp_ns)) * opt$scale_factor, 0)

trace <- within(trace, rm(timestamp_ns))

trace <- do.call("rbind", replicate(opt$repetition, trace, simplify = FALSE))

trace <- within(trace, acc_sum <- cumsum(interarrival_ns))

outputDir <- paste(inputDir, "_scale_", opt$scale_factor, "_reps_", opt$repetition, ".out", sep="")
print(paste("Saving output trace to", outputDir))

write.table(trace$acc_sum, outputDir, sep=" ", col.names = F, row.names = F)

#perform some additional analyses
# k <- 300
# timeseries <- table((trace$acc_sum%/% 1000000000 + 1) * 1000000000)
# timeseries_df <- data.frame(freq=as.vector(unname(timeseries))[1:k],intervals=(as.numeric(names(timeseries))/1000000000)[1:k])

# plot(timeseries_df$interval, timeseries_df$freq, ylab="Number of transmissions", xlab="Time (s)", main="Requests sent (1s intervals)", type="l", col = "blue", ylim=c(0,10000), xlim=c(0, k))

