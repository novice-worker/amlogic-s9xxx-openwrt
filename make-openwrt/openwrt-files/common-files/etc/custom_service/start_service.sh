#!/bin/bash
#====================================================
# Custom startup service for Rongpin King3399
# Platform : Rockchip RK3399 (AArch64)
#====================================================

custom_log="/tmp/ophub_start_service.log"

log_message() {
    echo "[$(date +"%Y.%m.%d.%H:%M:%S")] $1" >>"$custom_log"
}

log_message "===== Start custom service for Rongpin King3399 ====="

#--- Identify device type ----------------------------------------------------
MODEL=$(tr -d '\000' </proc/device-tree/model 2>/dev/null)
FDT_FILE=""
ophub_release_file="/etc/ophub-release"

[[ -f "$ophub_release_file" ]] && FDT_FILE=$(grep -oE 'meson.*dtb' "$ophub_release_file")
[[ -z "$FDT_FILE" && -f "/boot/uEnv.txt" ]] && FDT_FILE=$(grep -E '^FDT=.*\.dtb$' /boot/uEnv.txt | sed -E 's#.*/##')
[[ -z "$FDT_FILE" && -f "/boot/armbianEnv.txt" ]] && FDT_FILE=$(grep -E '^fdtfile=.*\.dtb$' /boot/armbianEnv.txt | sed -E 's#.*/##')
log_message "Detected FDT: ${FDT_FILE:-'none'} | Model: $MODEL"

#--- GPIO setup for Rongpin King3399 ----------------------------------------
if [[ "$MODEL" == "Rongpin King3399" ]]; then
    log_message "Configuring GPIO50 for fan control (GPIO56 reserved for restart)..."

    FAN_GPIO=50
    FAN_PATH="/sys/class/gpio/gpio${FAN_GPIO}"

    if [[ ! -d "$FAN_PATH" ]]; then
        echo "$FAN_GPIO" > /sys/class/gpio/export 2>/dev/null
        sleep 0.2
    fi

    if [[ -d "$FAN_PATH" ]]; then
        echo "out" > "${FAN_PATH}/direction" 2>/dev/null
        echo 1 > "${FAN_PATH}/value" 2>/dev/null
        log_message "GPIO50 set to HIGH (Fan ON)"
    else
        log_message "Failed to configure GPIO50 — sysfs export may be disabled."
    fi

    sleep 10
else
    log_message "Model not Rongpin King3399 — skipping GPIO setup."
fi

#--- Determine boot partition ------------------------------------------------
ROOT_PTNAME=$(df /boot 2>/dev/null | awk 'NR==2 {print $1}' | awk -F '/' '{print $3}')
if [[ -n "$ROOT_PTNAME" ]]; then
    log_message "Root partition: $ROOT_PTNAME"

    case "$ROOT_PTNAME" in
        mmcblk?p[0-9]*) DISK_NAME=$(echo "$ROOT_PTNAME" | sed -E 's/p[0-9]+$//'); PARTITION_NAME="p" ;;
        [hs]d[a-z][0-9]*) DISK_NAME=$(echo "$ROOT_PTNAME" | sed -E 's/[0-9]+$//'); PARTITION_NAME="" ;;
        nvme?n?p[0-9]*) DISK_NAME=$(echo "$ROOT_PTNAME" | sed -E 's/p[0-9]+$//'); PARTITION_NAME="p" ;;
        *) DISK_NAME=""; PARTITION_NAME=""; log_message "Unrecognized root partition format: $ROOT_PTNAME" ;;
    esac

    if [[ -n "$DISK_NAME" ]]; then
        PARTITION_PATH="/mnt/${DISK_NAME}${PARTITION_NAME}4"
        log_message "Derived disk: $DISK_NAME | Data partition: $PARTITION_PATH"
    fi
else
    log_message "Could not determine root partition."
fi

#--- Network performance optimization ---------------------------------------
if [[ -x "/usr/sbin/balethirq.pl" ]]; then
    perl /usr/sbin/balethirq.pl >/dev/null 2>&1
    log_message "Network optimization (balethirq.pl) executed."
else
    log_message "balethirq.pl not found — skipping network optimization."
fi

#--- Fan control service ----------------------------------------------------
if [[ -x "/usr/bin/pwm-fan.pl" ]]; then
    perl /usr/bin/pwm-fan.pl >/dev/null 2>&1 &
    log_message "Fan control (pwm-fan.pl) started in background."
else
    log_message "pwm-fan.pl not found — relying on GPIO50 static control."
fi

#--- Partition expansion (if required) --------------------------------------
todo_rootfs_resize="/root/.todo_rootfs_resize"
if [[ -f "$todo_rootfs_resize" && "$(cat "$todo_rootfs_resize" | xargs)" == "yes" ]]; then
    openwrt-tf >/dev/null 2>&1 || true
    log_message "Rootfs auto-expansion attempted."
fi

#--- Swap setup -------------------------------------------------------------
if [[ -n "$PARTITION_PATH" && -d "$PARTITION_PATH" ]]; then
    swap_file="${PARTITION_PATH}/.swap/swapfile"
    if [[ -f "$swap_file" ]]; then
        log_message "Enabling swap from $swap_file"
        loopdev=$(losetup -f)
        if [[ -n "$loopdev" ]]; then
            losetup "$loopdev" "$swap_file" 2>/dev/null
            swapon "$loopdev" 2>/dev/null && log_message "Swap enabled on $loopdev" || log_message "Failed to enable swap."
        fi
    fi
else
    log_message "Swap partition path not found or invalid: $PARTITION_PATH"
fi

log_message "===== All custom services processed successfully ====="
exit 0
