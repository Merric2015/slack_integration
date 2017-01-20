#!/bin/bash
# Author: Merric Reese
# Date: January 8th, 2017
# This script checks the disk utilisation on the server and sends a message to
# Slack using a web-hook if the disk utilisation is above certain thresholds
# Note: * If running from cron remember to re-direct the output to a file
#         or disable the echo statements.

# Copyright 2017 Merric Reese 

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#    http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#Enter the Slack Webhook URL in the following variable"
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/AAAAA/BBBBB/CCCCC"

##### SET Variable Defaults #####
DEBUG=false
DEBUG_TYPE="NULL"
REPORT=false
SEND_MESSAGE=false  # Flag to determine whether there is a message to send
SEND_TO_SLACK=true  # Option to send the message to slack webhook - Defult is to send the message
HOST=$(hostname)    # Hostname of the machine the script is running on 
MESSAGE="$HOST Disk\n"
DATE=$(date +%Y%m%d_%H%M%S)
USERNAME="\"username\": \"$HOST\""  #username to post as
#ICON="\"icon_url\": \"https://a.slack-edge.com/12b5a/plugins/tester/assets/service_36.png\""   #defaul icon
ICON="\"icon_emoji\": \":black_large_square:\""    # This can be cahnge to any slack emjoi

##### Set the drive warning and critical percentages #####
ROOT_PERC_WARNING=90    # 85% 92GB * 0.10 = 9.2GB Free
ROOT_PERC_CRITICAL=95   # 95% 92GB * 0.05 = 4.6GB Free
DATA_PERC_WARNING=90    # 90% 100GB * 0.10 = 10GB Free
DATA_PERC_CRITICAL=95   # 95% 100GB * 0.05 = 5GB Free
ZNAS_PERC_WARNING=93	# 93% 10.21T * 0.07 = 0.71T Free
ZNAS_PERC_CRITICAL=96	# 96% 10.21TB * 0.04 = 0.4T Free

##### Get Command Line Options #####
# Use -gt 0 to consume one or more arguments per pass in the loop (e.g.
# some arguments don't have a corresponding value to go with it such
# as in the --nosend example.
# Note that if 2 arguements then need to shift twice.
while [[ $# -gt 0 ]]
do
	# perform the following to convert all terms to lowercase for matching
	# don't do this if you have can sensitive options
	key=$(echo $1 | tr '[:upper:]' '[:lower:]')

	case $key in
    		-r|--report)
    			REPORT=true
    			shift # past argument
    			;;
    		-d|--debug)
			# use this if 2 parts to command - notice there are 2 shift commands
    			DEBUG=true
			CMD_VALUE=$(echo $2  | tr '[:upper:]' '[:lower:]')
			if [ "$CMD_VALUE" ]; then 
				#DEBUG_TYPE=$(echo $2  | tr '[:lower:]' '[:upper:]')
				if [ $CMD_VALUE == "warning" ] || [ $CMD_VALUE == "critical" ]; then 
					DEBUG_TYPE=$(echo $2  | tr '[:upper:]' '[:lower:]')
    					shift # past argument - Only perform this shift if the value matches an expected option
				fi
			fi
    			shift # past argument
    			;;
		-x|--nosend)
			SEND_TO_SLACK=false
			shift # pass argument
			;;
		-h|--help)
			#echo "usage: check_disk.sh [-d|--debug {critical|warning}] [-h|--help] [-r|--report] [-x|--nosend]"
			echo "usage: check_disk.sh [OPTION...]"
			echo "-d, --debug [critical, warning] : force sending message of type specified"
			echo "-h, --help     print this help message"
			echo "-r, --report   this will force a report on the the status of all current tracked disks"
			echo "-x, --nosend   will suppress message being sent to slack webhook"
			exit 0
			;;
    		*)
            		# unknown option
    			shift # past argument
    			;;
	esac
	#shift # past argument or value
done

if $DEBUG; then 
	echo ----- command line switches -----
	echo REPORT  = "${REPORT}"
	echo DEBUG   = "${DEBUG}"
	echo DEBUG_TYPE   = "${DEBUG_TYPE}"
	echo SEND_TO_SLACK = "${SEND_TO_SLACK}"
fi

# Get the state of the current disks
# Note: I'm sure this could be done simpler, but this works, so I left it at that.
# uses grep PERL expressions so /$ is the root mount point
DISKS=$(df -h | grep -P "/$|/data")
ROOT=$(echo "$DISKS" | grep -P "/$")
DATA=$(echo "$DISKS" | grep -P "/data")
ZNAS=$(sudo zfs list | grep -P "/znas$")

# extract the percentage without the % symbol using awk gsub to perform this
ROOT_PERC=$(echo "$ROOT" | awk '{gsub(/%/,"");print $5}')
ROOT_REMAINING=$(echo "$ROOT" | awk '{gsub(/%/,"");print $4}')
DATA_PERC=$(echo "$DATA" | awk '{gsub(/%/,"");print $5}')
DATA_REMAINING=$(echo "$DATA" | awk '{gsub(/%/,"");print $4}')

# needed to add the following to monitor the ZFS filesystem
ZNAS_PERC=$(echo "$ZNAS" | awk '{gsub(/T|G|M|K/,"");sum=$2+$3;perc=$2/sum*100;printf "%3.0f", perc }')
ZNAS_REMAINING=$(echo "$ZNAS" | grep -P "/znas$" | awk '{print $3 }')

## uncomment this to see output from DISK info
if $DEBUG; then 
	echo ----- Disk Info -----
	echo $DISKS
	echo root=$ROOT " %="$ROOT_PERC
	echo data01=$DATA " %="$DATA_PERC
	echo znas=$ZNAS " %="$ZNAS_PERC
fi

# Function to check Percentage utilisation and update MESSAGE
function fcheck_disk { #DISK, DISK_PERC, DISK_REMAINING, DISK_CRITICAL, DISK_WARNING
	# Check that the function was called with the right number of
	# parameters - otherwise exit with an error
	if [ $# -ne 5 ]; then 
		echo "ERROR: function fcheck_disk expects 4 variables - received $#"
		exit 1 #note: can use echo $? to get the exit code of the last command
	fi
	DISK=$1
	DISK_PERC=$2
	DISK_REMAINING=$3
	DISK_CRITICAL=$4
	DISK_WARNING=$5

	if [ "$DISK_PERC" -gt "$DISK_CRITICAL" ] || ( $DEBUG && [ $DEBUG_TYPE == "critical" ] ) ; then
		 MESSAGE="${MESSAGE}:no_entry: $DISK dirve is $DISK_PERC% full $DISK_REMAINING free :exclamation:\n"
		SEND_MESSAGE=true
	elif [ "$DISK_PERC" -gt "$DISK_WARNING" ] || ( $DEBUG && [ $DEBUG_TYPE == "warning" ] ); then
		MESSAGE="${MESSAGE}:warning: $DISK dirve is $DISK_PERC% full $DISK_REMAINING free\n"
		SEND_MESSAGE=true
	elif ( $REPORT ) || ( $DEBUG ) ; then
		MESSAGE="${MESSAGE}:white_check_mark: $DISK dirve is $DISK_PERC% full $DISK_REMAINING free. Warning level set @ ${DISK_WARNING}%\n"
		SEND_MESSAGE=true
	fi
}

# Call fcheck_disk for each disk / mount point
fcheck_disk "root" $ROOT_PERC $ROOT_REMAINING $ROOT_PERC_CRITICAL $ROOT_PERC_WARNING
fcheck_disk "data01" $DATA_PERC $DATA_REMAINING $DATA_PERC_CRITICAL $DATA_PERC_WARNING
fcheck_disk "znas" $ZNAS_PERC $ZNAS_REMAINING $ZNAS_PERC_CRITICAL $ZNAS_PERC_WARNING

# Now create the JSON object and send the final message if necessary
MESSAGE="${MESSAGE}$DATE\n"     # append the date to the message
if [ "$SEND_MESSAGE" == "true"  ] || ( $DEBUG ) ; then
        JSON_MESSAGE="{$USERNAME, $ICON, \"text\": \"$MESSAGE\"}"
	if $DEBUG; then 
		echo ----- Message -----
		echo MESSAGE = $DATE $MESSAGE
		echo JSON = $JSON_MESSAGE
	else
        	echo $DATE $JSON_MESSAGE
	fi
	if ${SEND_TO_SLACK}; then 
		# Only send the message if $SEND_TO_SLACK is true
               	curl --silent --connect-timeout 60 --max-time 300 -H "Content-Type: application/json" -X POST -d "$JSON_MESSAGE"  "$SLACK_WEBHOOK_URL" >/dev/null
	fi
fi

