insmod soc_can.ko \
    can0_is_enable=0 can0_dt=-1 can0_dr=-1 can0_cgu_clk_rate=-1 \
    can1_is_enable=1 can1_dt=PC09 can1_dr=PC10 can1_cgu_clk_rate=24000000 
ip link set can0 up type can bitrate 1000000
