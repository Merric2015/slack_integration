#!/bin/bash
# Author: Merric Reese
# Date: January 8th, 2017
# This script checks the disk utilisation on the server and sends a message to
# Slack using a web-hook if the disk utilisation is above certain thresholds.
# Note: * If running from cron remember to re-direct the output to a file
#         or disable the echo statements.
#       * This script outputs nothing unless disks are in a warning or 
#         critical state.
#       * Set DEBUG=true and lower disk percentages for testing.

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

#Enter the Slack Web-hook URL in the following variable"
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/AAAAAAAAAAAA/BBBBBBBBBBBB/CCCCCCCCCCCCC"

HOST=$(hostname)
MESSAGE="$HOST Disk\n"
ROOT_PERC_WARNING=90    # 90% 92GB * 0.10 = 9.2GB Free
ROOT_PERC_CRITICAL=95   # 95% 92GB * 0.05 = 4.6GB Free
DATA_PERC_WARNING=90    # 90% 100GB * 0.10 = 10GB Free
DATA_PERC_CRITICAL=95   # 95% 100GB * 0.05 = 5GB Free
ZNAS_PERC_WARNING=93	# 93% 10.21T * 0.07 = 0.71T Free
ZNAS_PERC_CRITICAL=96	# 96% 10.21TB * 0.04 = 0.4T Free
SEND_MESSAGE=false
DEBUG=false
DATE=$(date +%Y%m%d_%H%M%S)
USERNAME="\"username\": \"$HOST\""  #username to post as
#ICON="\"icon_url\": \"https://a.slack-edge.com/12b5a/plugins/tester/assets/service_36.png\""   #defaul icon
ICON="\"icon_emoji\": \":black_large_square:\""  # Replace this with any emoji or set ICON URL as above


# Get the state of the current disks
# Note: I'm sure this could be done simpler, but this works, so I left it at that.
# uses grep PERL expressions so /$ is the root mount point
DISKS=$(df -h | grep -P "/$|/data")
ROOT=$(echo "$DISKS" | grep -P "/$")
DATA=$(echo "$DISKS" | grep -P "/data")
#ZNAS=$(sudo zfs list | grep -P "/znas$" | awk '{gsub(/T|G|M|K/,"");sum=$2+$3;perc=$2/sum*100;print $2 " " $3 " " sum " " perc }')

# extract the percentage without the % symbol using awk gsub to perform this
ROOT_PERC=$(echo "$ROOT" | awk '{gsub(/%/,"");print $5}')
DATA_PERC=$(echo "$DATA" | awk '{gsub(/%/,"");print $5}')
# needed to add the following to monitor the ZFS filesystem
ZNAS_PERC=$(sudo zfs list | grep -P "/znas$" | awk '{gsub(/T|G|M|K/,"");sum=$2+$3;perc=$2/sum*100;printf "%3.0f", perc }')

## uncomment this to see output from DISK info
#echo $DISKS
#echo root=$ROOT " %="$ROOT_PERC
#echo data01=$DATA " %="$DATA_PERC
#echo $ZNAS_PERC

# Function to check Percentage utilisation and update MESSAGE
function fcheck_disk { # DISK_NAME, DISK_PERC, DISK_CRITICAL, DISK_WARNING
	# Check that the function was called with the right number of
	# parameters - otherwise exit with an error
	if [ $# -ne 4 ]; then 
		echo "ERROR: function fcheck_disk expects 4 variables - received $#"
		exit 1 #note: can use echo $? to get the exit code of the last command
	fi
	DISK_NAME=$1
	DISK_PERC=$2
	DISK_CRITICAL=$3
	DISK_WARNING=$4
	# Check the status of the disks / mount points 
	# Note: Check is performed in decending order of criticality as
	# this makes compiling MESSAGE easier.
	if [ "$DISK_PERC" -gt "$DISK_CRITICAL" ]; then
		 MESSAGE="${MESSAGE}:no_entry: $DISK_NAME dirve is $DISK_PERC% full :exclamation:\n"
		SEND_MESSAGE=true
	elif [ "$DISK_PERC" -gt "$DISK_WARNING" ]; then
		MESSAGE="${MESSAGE}:warning: $DISK_NAME dirve is $DISK_PERC% full\n"
		SEND_MESSAGE=true
	fi
}

# Call fcheck_disk for each disk / mount point
fcheck_disk "root" $ROOT_PERC $ROOT_PERC_CRITICAL $ROOT_PERC_WARNING
fcheck_disk "data01" $DATA_PERC $DATA_PERC_CRITICAL $DATA_PERC_WARNING
fcheck_disk "znas" $ZNAS_PERC $ZNAS_PERC_CRITICAL $ZNAS_PERC_WARNING

# Now create the JSON object and send the final message if necessary
MESSAGE="${MESSAGE}$DATE\n"     # append the date to the message
if [ "$SEND_MESSAGE" == "true" ]; then
        JSON_MESSAGE="{$USERNAME, $ICON, \"text\": \"$MESSAGE\"}"
        if [ "$DEBUG" == "true" ]; then
                echo "$MESSAGE"
                echo $JSON_MESSAGE
                #curl --silent --connect-timeout 60 --max-time 300 -H "Content-Type: application/json" -X POST -d "$JSON_MESSAGE"  "$SLACK_WEBHOOK_URL" >/dev/null
        else
                curl --silent --connect-timeout 60 --max-time 300 -H "Content-Type: application/json" -X POST -d "$JSON_MESSAGE"  "$SLACK_WEBHOOK_URL" >/dev/null
                echo $DATE $JSON_MESSAGE   # use this for logging or disable if not required.
        fi
fi

