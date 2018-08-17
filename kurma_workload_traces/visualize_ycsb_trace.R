#!/usr/bin/env Rscript

list.of.packages <- c("optparse")
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages, repos = "http://cran.us.r-project.org")

getFileName <- function(path)
{
	x <- unlist(strsplit(path, "/"))
	return(x[length(x)])
}

library("optparse")

option_list = list(
make_option(c("-af", "--actual_ts_file"), type="character",
default=NULL, help="actual timestamp trace file name", metavar="character"),
make_option(c("-if", "--intended_ts_file"), type="character",
default=NULL, help="intended timestamp trace file name", metavar="character"),
make_option(c("-d", "--duration"), type="integer",
default=.Machine$integer.max, help="duration in sec", metavar="number"),
make_option(c("-i", "--interval"), type="integer",
default=1, help="interval in sec", metavar="number"),
make_option(c("-w", "--warmup"), type="integer",
default=60, help="warmup period in sec", metavar="number"),
make_option(c("-id", "--id"), type="character",
default="", help="Optional string appendix to the generated file, to differentiate traces", metavar="character"))

opt_parser = OptionParser(option_list=option_list)

opt = parse_args(opt_parser)

if (is.null(opt$intended_ts_file))
{
	print_help(opt_parser)
	stop("A trace file must be supplied for intended timetamps", call.=FALSE)
}

j <- opt$interval*1000000000

start <- Sys.time()

actual_length = .Machine$integer.max

if(!is.null(opt$actual_ts_file))
{
	actual <- read.table(opt$actual_ts_file, sep=" ", header=FALSE, fill=TRUE)
	colnames(actual)[1] <- "thread_id"
	colnames(actual)[2] <- "R"
	colnames(actual)[3] <- "time"
	#remove invalid rows
	actual <- actual[,c("thread_id", "R", "time")]
	actual <- na.omit(actual)
	actual <- table((actual$time %/% j + 1) * j)
	actual_length <- length(actual)
}

intended <- read.table(opt$intended_ts_file, sep=" ", header=FALSE)
colnames(intended)[1] <- "time"
intended$time <- intended$time + opt$warmup * 1e9
intended <- table((intended%/% j + 1) * j)

intended_k <- min(c(floor(opt$duration/opt$interval), length(intended)))

intended_df <- data.frame(freq=as.vector(unname(intended))[1: intended_k],intervals=(as.numeric(names(intended))/1000000000)[1: intended_k])
intended_file_name <- getFileName(opt$intended_ts_file)
actual_file_name <- NULL

actual_k <- 0
actual_min_freq <- .Machine$integer.max
actual_max_freq <- 0
if(!is.null(opt$actual_ts_file))
{
	actual_k <- min(c(floor(opt$duration/opt$interval), actual_length))
	actual_df <- data.frame(freq=as.vector(unname(actual))[1: actual_k],intervals=(as.numeric(names(actual))/1000000000)[1: actual_k])
	actual_file_name <- getFileName(opt$actual_ts_file)
	actual_min_freq <- min(actual_df$freq)
	actual_max_freq <- max(actual_df$freq)
}


outputFile <- paste("requests_sent_1s_timeseries_", opt$duration, "_", opt$interval, "_", intended_file_name, "_", actual_file_name, "_", (opt$id), ".pdf", sep="")

pdf(outputFile, width=8, height=6)
plot(intended_df$interval, intended_df$freq, ylab="Number of transmissions", xlab="Time (s)", main=paste("Requests sent (", opt$interval, "s intervals)", sep=""), type="l", col = "blue", xlim=c(opt$interval, max(intended_k, actual_k)*opt$interval), ylim=c(min(intended_df$freq,actual_min_freq),max(intended_df$freq,actual_max_freq)))

if(!is.null(opt$actual_ts_file))
{
	lines(actual_df $interval, actual_df $freq, type = "l", col = "red")
	legend("topleft", c("Intended","Actual (non-spinning)"),lty=c(1,1), lwd=c(2.5,2.5),col=c("blue","red"))
}
dev.off()

end <- Sys.time()

print(paste("Plot has been generated [Elapsed time:", end-start, "s]"))
print(paste("Output graph saved to:", outputFile))

#calculate percentage difference
if(!is.null(opt$actual_ts_file))
{	
start <- Sys.time()
delay_interval <- actual_k-intended_k
diff = mean(abs(as.vector(unname(intended))[delay_interval:actual_k-delay_interval] - as.vector(unname(actual))[(delay_interval+1):actual_k])/ as.vector(unname(intended))[delay_interval:actual_k-delay_interval] * 100)
end <- Sys.time()
print(paste("Percentage error between the two curves:", diff, "% [Elapsed time:", end-start, "s]"))
}
