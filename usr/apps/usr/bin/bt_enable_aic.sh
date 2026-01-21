#!/bin/sh
tty_dev=/dev/ttyS1

killall hciattach

bt_test -s uart 115200 $tty_dev &
sleep 1
hciattach -s 115200 $tty_dev any 115200 flow nosleep &
sleep 1
/usr/libexec/bluetooth/bluetoothd -n -C &
