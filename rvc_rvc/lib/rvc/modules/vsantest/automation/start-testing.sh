#!/bin/bash

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/var/opt/OpenJDK-1.8.0.92-bin/bin:/var/opt/OpenJDK-1.8.0.92-bin/jre/bin
export HOME=/root
 
SCRIPTNAME="/opt/automation/lib/start-testing.rb"
PIDFILE=/var/run/start-testing.rb.pid

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

if ps aux | grep $SCRIPTNAME | grep -q ruby; then
  echo "Script already running! Exiting"
  exit 255
else
  rm -f $DIR/logs/*.log
  nohup ruby $DIR/lib/start-testing.rb > $DIR/logs/all-in-one-testing.log 2>&1 &
  RESULT=`ps -ef | grep ${SCRIPTNAME} | grep ruby`
  PID=`echo ${RESULT}|awk '{ print $2 }'`
  echo $PID > $PIDFILE
fi

