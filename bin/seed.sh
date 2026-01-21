#! /bin/sh
source /etc/profile

part_userdata_name="userdata"
part_userdata_devblk="/dev/mmcblk0p10"
part_userdata_mount="/usr/data"

part_deplibs_name="deplibs"
part_deplibs_devblk="/dev/mmcblk0p7"
part_deplibs_signature_devblk="/dev/mmcblk0p1"
part_deplibs_mount="/usr/deplibs"

part_apps_name="apps"
part_apps_devblk="/dev/mmcblk0p8"
part_apps_mount="/usr/apps"

part_sn_mac_name="sn_mac"
part_sn_mac_devblk="/dev/mmcblk0p2"

userdata_err_flag="false"
mount_do_userdata()
{
    if [ ! -b "${part_userdata_devblk}" ]; then
        echo "Blkdev ${part_userdata_devblk} inexistence !" > /dev/console
        return -1
    fi

    mkdir -p ${part_userdata_mount}
    if fsck -y -t ext4 "$part_userdata_devblk" > /dev/null; then
        if ! mount -t ext4 -o sync,data=ordered,barrier=1 ${part_userdata_devblk} ${part_userdata_mount} > /dev/null; then
            echo "Mount partition ${part_userdata_name} fail" > /dev/console
            return -1
        fi
    else
        userdata_err_flag="true"
        if ! mke2fs -F -t ext4 -E lazy_itable_init=0,lazy_journal_init=0 ${part_userdata_devblk} > /dev/null; then
            echo "Blkdev ${part_userdata_devblk} mk2fs fail !" > /dev/console
            return -1
        fi

        echo "Blkdev ${part_userdata_devblk} mk2fs over !" > /dev/console
        if ! mount -t ext4 -o sync,data=ordered,barrier=1 ${part_userdata_devblk} ${part_userdata_mount} > /dev/null; then
            echo "Mount partition ${part_userdata_name} fail" > /dev/console
            return -1
        fi
    fi

    return 0
}


mount_do_deplibs()
{
    cmd_sc -v src=${part_deplibs_devblk} > /dev/console 2>&1
    if [ $? -ne 0 ]; then
        echo "Verify partition ${part_deplibs_name} fail" > /dev/console
        halt
    fi

    losetup -o 2048 /dev/loop0 "${part_deplibs_devblk}"
    if ! mount -t squashfs /dev/loop0 "${part_deplibs_mount}"; then
        echo "Mount partition ${part_deplibs_name} fail" > /dev/console
        return 1
    fi
    return 0
}


mount_do_apps()
{
    if [ "${userdata_err_flag}" == "true" ]; then
        resize2fs ${part_apps_devblk} > /dev/null
        echo "Resize2fs ${part_apps_devblk} finish" > /dev/console
    fi

    if ! mount -t ext4 -o sync,data=ordered,barrier=1 "${part_apps_devblk}" "${part_apps_mount}"; then
        echo "Mount partition ${part_apps_name} fail" > /dev/console
        return 1
    fi

    return 0
}


verify_apps()
{
    encrypted=1
    if [ $encrypted -eq 1 ]; then
        mkdir -p /tmp/apps
    fi
    apps="alchemistp nexusp onyxp quintusp thirteenthp solusp vectorp mdns"
    for app in $apps
    do
        if [ $encrypted -eq 1 ]; then
            cmd_sc src=${part_apps_mount}/usr/bin/$app.bin dst=/tmp/apps/$app > /dev/console 2>&1
        else
            cmd_sc -v src=${part_apps_mount}/usr/bin/$app > /dev/console 2>&1
        fi
        if [ $? -ne 0 ]; then
            echo "Verify $app fail" > /dev/console
            halt
        fi
        if [ $encrypted -eq 1 ]; then
            chmod 755 /tmp/apps/$app
        fi
    done
}


check_login_permission()
{
    if [ -f /etc/shadow_security ]; then
        if [ -f ${part_userdata_mount}/permission ]; then
            if [ ! -f ${part_userdata_mount}/permission.chk ]; then
                echo 1 > ${part_userdata_mount}/permission.chk
                cmd_sc -v src=${part_userdata_mount}/permission > /dev/null 2>&1
                if [ $? -eq 0 ]; then
                    mac=$(cut -d';' -f2 /tmp/params)
                    line=$(grep -i ${mac} ${part_userdata_mount}/permission)
                    if [ -n "$line" ]; then
                        sed -i 's/^!creality/creality/' /tmp/shadow
                        if echo "$line" | grep -q "root"; then
                            sed -i 's/^!root/root/' /tmp/shadow
                        fi
                    fi
                fi
            fi
            rm -rf ${part_userdata_mount}/permission.chk
        fi
        chattr +i /tmp/shadow
    fi
}


decrypt_sn_mac()
{
    len=$(printf "%d" "0x$(head -c4 ${part_sn_mac_devblk})")
    dd if=${part_sn_mac_devblk} of=/tmp/sn_mac.bin bs=1 skip=4 count=$len
    base64 -d /tmp/sn_mac.bin /tmp/sn_mac.signed
    cmd_sc src=/tmp/sn_mac.signed dst=/tmp/params > /dev/console 2>&1
    if [ $? -ne 0 ]; then
        echo "Decrypt partition ${part_sn_mac_name} fail" > /dev/console
        halt
    else
        chmod 644 /tmp/params
    fi
    rm -rf /tmp/sn_mac.bin
    rm -rf /tmp/sn_mac.signed

    return 0
}


resize_apps()
{
    blkname=${part_apps_devblk}
    resize2fs ${blkname} > /dev/null
    echo "Resize2fs ${blkname} finish" > /dev/console
}


modify_date()
{
    if [ "" != "`ps | grep ntpd | grep -v grep`" ]; then
        return 0
    fi

    strtime=$1
    tm="`echo ${strtime} | sed -E 's/(....)(..)(..)(..)(..)(..)/\1-\2-\3 \4:\5:\6/'`"
    if ! date -s "${tm}"; then
        echo "Set time [${tm}] fail" > /dev/console
        return 1
    fi

    return 0
}

init_sys_date()
{
    if [ "1970-01-01" != "$(date +"%Y-%m-%d")" ]; then
        return 0
    fi

    local buildtime_file="/usr/apps/etc/buildtime"
    if [ ! -f "$buildtime_file" ]; then
        echo "Error: $buildtime_file not found."
        return 1
    fi

    target_time=$(cat "$buildtime_file")
    if ! date -s "${target_time}"; then
        echo "Set time [${target_time}] fail"> /dev/console
        return 1
    fi

    return 0
}

upgmode=""
upgfile=""
strdate=""
upgdir="${part_userdata_mount}/upgrade"
upg_check_flag()
{
    upgstate=${upgdir}/state

    if [ ! -d "${upgdir}" -o ! -f "${upgstate}" ]; then
        #echo "Not set upgrade flag" > /dev/console
        return 1;
    fi

    hasupg="false"
    while IFS= read -r line; do
        if echo "${line}" | grep -qE '^#'; then
            continue
        fi
        nline=${line// /}
        key=$(echo "$nline" | awk -F':' '{print $1}')
        val=$(echo "$nline" | awk -F':' '{print $2}')
        if [ "${key}" == "action" -a "${val}" == "upg" ]; then
            hasupg="true"
        elif [ "${key}" == "mode" -a "${val}" != "" ]; then
            upgmode=${val}
        elif [ "${key}" == "path" -a "${val}" != "" ]; then
            upgfile=${val}
        elif [ "${key}" == "date" -a "${val}" != "" ]; then
            strdate=${val}
        fi
    done < "${upgstate}"

    if [ "${hasupg}" != "true" -o "${upgfile}" == "" ]; then
        echo "Check ${upgstate} nopass !" > /dev/console
        return 1
    fi

    return 0
}


upg_wait_mobiledisk()
{
    now_wait_count=0
    max_wait_count=100
    while true; do
        if mount | grep "/dev/sd[a-z]"; then
            break
        fi
        let "now_wait_count++"
        if [ $now_wait_count -ge $max_wait_count ]; then
            echo "Not find mobile disk to mount !" > /dev/console
            break
        fi
        sleep 0.1
    done
}


disktype="0"
upg_check_disk()
{
    while IFS= read -r line; do
        tymmc="`echo` ${line} |grep `mmcblk0`"
        tynand="`echo` ${line} |grep `mtd`"
        if [ "${tymmc}" != "" ]; then
            #echo "Disk type mmc" > /dev/console
            disktype="0"
            return 0
        fi

        if [ "${tynand}" != "" ]; then
            #echo "Disk type nand" > /dev/console
            disktype="1"
            return 0
        fi

    done < "/proc/partitions"

    disktype="0"
    return 0
}


err_flag_path="${part_userdata_mount}/.errflag"
handle_err_flag()
{
    opt=$1
    if [ "$opt" == "set" ]; then
        touch -t `date +"%Y%m%d%H%M.%S"` ${err_flag_path}
        sync
        return 0

    elif [ "$opt" == "get" ]; then
        if [ -f "${err_flag_path}" ]; then
            return 0
        fi
        return 1

    elif [ "$opt" == "clean" ]; then
        if [ -f "${err_flag_path}" ]; then
            rm ${err_flag_path}
            sync
        fi
        return 0
    fi

    return 1
}

upgresult="${upgdir}/upgresult"
upg_do()
{
    if ! upg_check_flag; then
        return 1
    fi

    if [ "${upgmode}" == "external" ]; then
        echo "Wait mobile disk to mount !" > /dev/console
        upg_wait_mobiledisk
    fi

    if [ ! -f "${upgfile}" ]; then
        echo "Upgrade package ${upgfile} inexistence !" > /dev/console
        echo "upgresult: file_inexistence" > ${upgresult}
        return 1
    fi

    if [ -f ${upgdir}/verify ]; then
        read count < ${upgdir}/verify
        if [ $count -ge 3 ]; then
            echo "Verify package ${upgfile} fail too many times !" > /dev/console
            echo "upgresult: verify_fail" > ${upgresult}
            rm ${upgdir}/verify
            return 1
        else
            echo $((count+1)) > ${upgdir}/verify
        fi
    else
        echo 1 > ${upgdir}/verify
    fi
    cmd_sc -v src=${upgfile} > /dev/console 2>&1
    if [ $? -ne 0 ]; then
        echo "Verify package ${upgfile} fail" > /dev/console
        echo "upgresult: verify_fail" > ${upgresult}
        rm ${upgdir}/verify
        return 1
    fi
    rm ${upgdir}/verify

    upg_check_disk
    modify_date "${strdate}"
    logfile="${upgdir}/`date +\"%Y%m%d%H%M%S\"`".log
    if ! touch "${logfile}"; then
        echo "Detection ${upgdir} file system happen error !" > /dev/console
        need_restore_flag="true"
        umount ${part_userdata_mount} && mount_do_userdata
    fi

    if ! handle_err_flag "get"; then
        handle_err_flag "set"
    else
        need_restore_flag="true"
        echo "Detection before happen breakoff error !" > /dev/console
    fi

    echo "Run upgrade ${upgfile} start" > /dev/console
    if ! upgbox -U -f "${upgfile}" -t "${disktype}" -l "${logfile}" &> /dev/console; then
        echo "Upgrade run fail !" > /dev/console
        echo "upgresult: failed" > ${upgresult}
        echo "upgdate: `date +\"%Y%m%d%H%M%S\"`" >> ${upgresult}
        exit 1
    fi

    if [ "${upgmode}" == "interior" ]; then
        rm ${upgfile}
    fi

    rm ${upgdir}/state
    handle_err_flag "clean"
    echo "Run upgrade ${upgfile} finish" > /dev/console
    echo "upgresult: succeed" > ${upgresult}
    echo "upgdate: `date +\"%Y%m%d%H%M%S\"`" >> ${upgresult}

    sync && umount ${part_userdata_mount}
    resize_apps
    return 0
}


reset_clean_list_file="${part_userdata_mount}/clean_list"
do_reset_clean()
{
    if [ ! -f ${reset_clean_list_file} ]; then
        return 0
    fi

    echo "Run reset ..." > /dev/console

    while read cls mode
    do
        if [ -d ${cls} ]; then
            if [ "${mode}" == "-d" ]; then
                rm -rf ${cls}
            else
                rm -rf ${cls}/*
            fi

            continue
        fi

        if [ -f ${cls} ]; then
            rm -rf ${cls}
        fi
    done < "${reset_clean_list_file}"

    if [ -d ${upgdir} ]; then
        rm -rf ${upgdir}/*.log
    fi

    rm -rf ${reset_clean_list_file}
    need_restore_flag="true"
    umount ${part_userdata_mount} && mount_do_userdata
}


run_system_service()
{
    for i in /etc/appetc/init.d/S??*; do
        [ ! -f "$i" ] && continue

        case "$i" in
        *.sh)
            (
            trap - INT QUIT TSTP
            set start
            . $i
            )
            ;;
        *)
            $i start
            ;;
        esac
    done
}

run_creality_service()
{
    for i in /etc/appetc/init.d/CS??*; do
        [ ! -f "$i" ] && continue

        case "$i" in
        *.sh)
            (
            su -c "trap - INT QUIT TSTP" creality
            su -c "set start" creality
            su -c ". $i" creality
            )
            ;;
        *)
            su -c "$i start" creality
            ;;
        esac
    done
}


wait_system()
{
    now_wait_count=0
    max_wait_count=50
    while true; do
        if [ -e "/dev/mmcblk0" ]; then
            break
        fi
        let "now_wait_count++"
        if [ $now_wait_count -ge $max_wait_count ]; then
            echo "The partition table not found!" > /dev/console
            break
        fi
        sleep 0.1
    done
}


main()
{
    insmod /lib/modules/soc_security.ko

    wait_system

    if mount_do_userdata; then
        if upg_do; then
            reboot && exit 0
        fi

        do_reset_clean
    fi

    ulimit -c unlimited
    mkdir -p /usr/data/core
    echo "|/bin/core_helper %e" > /proc/sys/kernel/core_pattern

    decrypt_sn_mac
    mount_do_deplibs
    mount_do_apps
    verify_apps
    check_login_permission
    init_sys_date
    run_system_service
    run_creality_service
    return 0
}

main
