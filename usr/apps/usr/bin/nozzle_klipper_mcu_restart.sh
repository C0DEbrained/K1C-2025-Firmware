#!/bin/sh

DEVICE_TYPE=0xA1
DEVICE=/dev/ttyS3
BAUDRATE=230400
FIRMWARE=/lib/firmware/klipper_nozzle_serial_app.bin
LOGFILE=/usr/data/printer_data/logs/cmd_iap_nozzle_klipper.log

#reboot enter bootrun
cmd_gpio set_func PB23 func3 > $LOGFILE 2>&1
cmd_gpio set_func PB23 pull_hiz >> $LOGFILE 2>&1
cmd_gpio set_func PB25 func3 >> $LOGFILE 2>&1
cmd_gpio set_func PB25 pull_hiz >> $LOGFILE 2>&1
cmd_gpio set_func PC04 output0 >> $LOGFILE 2>&1
sleep 1
cmd_gpio set_func PC04 output1 >> $LOGFILE 2>&1
sleep 1
cmd_gpio set_func PB23 func1 >> $LOGFILE 2>&1
cmd_gpio set_func PB25 func1 >> $LOGFILE 2>&1

mkdir -p /usr/data/printer_data/logs

echo "[`date "+%Y-%m-%d %H:%M:%S"`] start nozzle mcu restart..." >> $LOGFILE 2>&1

sh /usr/apps/usr/bin/mcu_iap_upgrade.sh SERIAL $DEVICE_TYPE $DEVICE $BAUDRATE $FIRMWARE | sed '/progress/d' >> $LOGFILE 2>&1
