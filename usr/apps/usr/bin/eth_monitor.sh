#!/bin/sh

log_file=/usr/data/printer_data/logs/eth.log

trace_log()
{
    if [ -f /usr/data/creality/debug/trace_eth ] ;
    then
        printf "`date`: $1\n" >> $log_file
    fi
}



start_udhcpc() {

	if ! ps |grep "udhcpc -i eth0"|grep -v grep
	then
		trace_log "udhcpc not run,will be run"
		/sbin/udhcpc -i eth0 -s /usr/apps/usr/bin/udhcpc_eth.sh &
	else
		trace_log "udhcpc  run already, refresh"
        ps |grep "udhcpc -i eth0"|grep -v grep|awk '{print $1}' |xargs kill -USR2 
        usleep 100000
        ps |grep "udhcpc -i eth0"|grep -v grep|awk '{print $1}' |xargs kill -USR1
	fi
}

start_ifconfig() {

    if ! /sbin/ifconfig eth0 |grep UP
    then
        trace_log "eth0 down, /sbin/ifconfig eth0 up"
        /sbin/ifconfig eth0 up
    # else
    #     trace_log "up already"
    fi
}


check_eth0() {

	if [ -f /sys/class/net/eth0/carrier ]
	then
		if cat /sys/class/net/eth0/carrier |grep 1
        then
            trace_log "eth plug in when start"
            start_ifconfig
            start_udhcpc
        else
            trace_log "not 1 /sys/class/net/eth0/carrier"         
        fi
    else
        trace_log "not exist /sys/class/net/eth0/carrier"
	fi
}

model_=`creality_sn read  creality_model_str`
model="$(echo $model_ | tr '[:upper:]' '[:lower:]')"

if [ x$model = x"k1max" ]
then
    start_ifconfig
    start_udhcpc
    # check_eth0
    trace_log "to start ip monitor"
    /sbin/ip monitor link dev eth0 | while read -r line; do
    if echo "$line" |grep "state DOWN"; then
        trace_log "eth plug out"
        #refresh 
        start_udhcpc
        
    elif echo "$line" |grep "state UP"; then
        trace_log "eth plug in"
        start_ifconfig
        start_udhcpc
        
    fi
    done
else
    trace_log "not support model : $model"
fi


exit 0
