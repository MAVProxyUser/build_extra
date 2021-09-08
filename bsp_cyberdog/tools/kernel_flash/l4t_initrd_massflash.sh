#!/bin/bash

# Copyright (c) 2021, NVIDIA CORPORATION. All rights reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

# Usage: ./l4t_initrd_massflash [ --showlogs ]
# This script execute the massflash process using the mass flash package

function printerror()
{
    echo "Unable to enter the flash environment."
    echo "Number of devices have exceed the maximum supported"
    echo "or you have not run generate flash package"
    exit 1
}

function usage()
{
	echo -e "
Usage: $0 [ --showlogs ]
Where,
    --showlogs                     Spawn gnome-terminal to show individual flash process logs
	"; echo;
	exit 1
}


opstr+="-:"
while getopts "${opstr}" OPTION; do
	case $OPTION in
	-) case ${OPTARG} in
	   showlogs)
		showlogs=1
		;;
	   *) usage ;;
	   esac;;
	*)
	   usage
	   ;;
	esac;
done


# Find devices to flash
# shellcheck disable=SC2207
devpaths=($(find /sys/bus/usb/devices/usb*/ -name devnum -print0 | {
	found=()
	while read -r -d "" fn_devnum; do
		dir="$(dirname "${fn_devnum}")"
		vendor="$(cat "${dir}/idVendor")"
		if [ "${vendor}" != "0955" ]; then
			continue
		fi
		product="$(cat "${dir}/idProduct")"
		case "${product}" in
		"7018") ;; # TX2i
		"7c18") ;; # TX2
		"7019") ;; # AGX Xavier
		"7e19") ;; # AGX 8GB
		"7418") ;; # TX2 4GB
		*)
			continue
			;;
		esac
		fn_busnum="${dir}/busnum"
		if [ ! -f "${fn_busnum}" ]; then
			continue
		fi
		fn_devpath="${dir}/devpath"
		if [ ! -f "${fn_devpath}" ]; then
			continue
		fi
		busnum="$(cat "${fn_busnum}")"
		devpath="$(cat "${fn_devpath}")"
		found+=("${busnum}-${devpath}")
	done
	echo "${found[@]}"
}))


# Exit if no devices to flash
if [ ${#devpaths[@]} -eq 0 ]; then
	echo "No devices to flash"
	exit 1
fi



showlogs=0
count=0
pid="$$"
ts=$(date +%Y%m%d-%H%M%S);

L4T_INITRD_FLASH_DIR="$(cd "$(dirname "${0}")" && pwd)"
L4T_TOOLS_DIR="${L4T_INITRD_FLASH_DIR%/*}"
LINUX_BASE_DIR="${L4T_TOOLS_DIR%/*}"

mkdir -p "${LINUX_BASE_DIR}/masslog/"
for devpath in "${devpaths[@]}"; do
 	fn_log="${LINUX_BASE_DIR}/masslog/${ts}_${pid}_flash_${devpath}.log"
    original_cmd="${L4T_INITRD_FLASH_DIR}/l4t_initrd_flash.sh"
	cmd_param="$(cat "${LINUX_BASE_DIR}/massinitrdflash/flashparam.txt")"
 	cmd="${original_cmd} --usb-instance ${devpath} --mass-flash ${count} --flash-only ${cmd_param}";
    echo "${cmd}"
 	eval "${cmd}" > "${fn_log}" 2>&1 &
 	flash_pid="$!";
 	flash_pids+=("${flash_pid}")
 	echo "Start flashing device: ${devpath}, PID: ${flash_pid}";
 	if [ ${showlogs} -eq 1 ]; then
 		gnome-terminal -e "tail -f ${fn_log}" -t "${fn_log}" > /dev/null 2>&1 &
 	fi;
    count=$((count + 1))
done

 # Wait until all flash processes done
failure=0
while true; do
	running=0
	if [ ${showlogs} -ne 1 ]; then
		echo -n "Ongoing processes:"
	fi;
	new_flash_pids=()
	for flash_pid in "${flash_pids[@]}"; do
		if [ -e "/proc/${flash_pid}" ]; then
			if [ ${showlogs} -ne 1 ]; then
				echo -n " ${flash_pid}"
			fi;
			running=$((running + 1))
			new_flash_pids+=("${flash_pid}")
		else
			wait "${flash_pid}" || failure=1
		fi
	done
	if [ ${showlogs} -ne 1 ]; then
		echo
	fi;
	if [ ${running} -eq 0 ]; then
		break
	fi
	flash_pids=("${new_flash_pids[@]}")
	sleep 5
done

if [ ${failure} -ne 0 ]; then
	echo "Flash complete (WITH FAILURES)";
	exit 1
fi
