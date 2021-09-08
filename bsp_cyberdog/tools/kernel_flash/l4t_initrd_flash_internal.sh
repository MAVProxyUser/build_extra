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

# Usage: ./l4t_initrd_flash_internal.sh [ --external-device <ext> -c <cfg> -S <SIZE> ] <target> <rootfs_dir>
# This script contains the core functionality of initrd flash

set -eo pipefail

L4T_INITRD_FLASH_DIR="$(cd "$(dirname "${0}")" && pwd)"
L4T_TOOLS_DIR="${L4T_INITRD_FLASH_DIR%/*}"
LINUX_BASE_DIR="${L4T_TOOLS_DIR%/*}"
BOOTLOADER_DIR="${LINUX_BASE_DIR}/bootloader"
ROOTFS_DIR="${LINUX_BASE_DIR}/rootfs"
NFS_IMAGES_DIR="${L4T_INITRD_FLASH_DIR}/images"
INITRDDIR_L4T_DIR="${L4T_INITRD_FLASH_DIR}/initrd_flash"
KERNEL_FLASH_SCRIPT="l4t_flash_from_kernel.sh"
FLASH_IMG_MAP="initrdflashimgmap.txt"
nargs=$#;
target_rootdev=${!nargs};
nargs=$((nargs-1));
target_board=${!nargs};
working_dir=$(mktemp -d)
TEMP_INITRD_FLASH_DIR=""
CHIPID=$(LDK_DIR=${LINUX_BASE_DIR}; source "${LDK_DIR}/${target_board}.conf";echo "${CHIPID}")



CREATE_FLASH_SCRIPT="${L4T_INITRD_FLASH_DIR}/l4t_create_flash_image_in_nfs.sh"

trap cleanup EXIT

cleanup()
{
	if [ -n "${qspi}" ] && ! wait "${qspi}"; then
		echo "Error flashing qspi"
	fi
	echo "Cleaning up..."
	[ -z "${keep}" ] && rm -rf "${working_dir}"
	if [ -n "${device_instance}" ]; then
		DEST_FOLDER=${LINUX_BASE_DIR}/temp_initrdflash
		[ -z "${keep}" ] && [ -z "${reuse}" ] && rm -rf "${DEST_FOLDER}/bootloader${device_instance}"
	fi
	if [ -n "${keep}" ]; then
		echo "Keeping working dir at ${DEST_FOLDER}/bootloader${device_instance} and ${working_dir}"
	fi
}

check_prerequisite()
{

	if ! command -v sshpass &> /dev/null
	then
		echo "ERROR sshpass not found! To install - please run: " \
				"\"sudo apt-get install sshpass\""
		exit 1
	fi

	if ! command -v abootimg &> /dev/null
	then
		echo "ERROR abootimg not found! To install - please run: " \
				"\"sudo apt-get install abootimg\""
		exit 1
	fi

	if ! command -v nmcli &> /dev/null
	then
		echo "ERROR nmcli not found! To install - please run: " \
				"\"sudo apt-get install network-manager\""
		exit 1
	fi

	if [ -n "${external_device}" ]; then
		if [ -z "${config_file}" ]; then
			echo "Flashing external device required that -c option is \
specified"
			exit 1
		fi
	fi
}

generate_flash_package()
{
    local cmd
    cmd=("${CREATE_FLASH_SCRIPT}")
    cmd+=("--no-flash" "-t")
	if [ -n "${external_device}" ]; then
		# Choose a random, valid external device here. Initrd flash will
		# overwrite external-device param.
		cmd+=("--external-device" \
		"${external_device}" "-c" "${config_file}")
		if [ -n "${external_size}" ]; then
			cmd+=("-S" "${external_size}")
		fi
	fi

	if [ -n "${external_only}" ]; then
		cmd+=("${external_only}")
	fi

	if [ -n "${OPTIONS}" ]; then
		cmd+=("-p" "${OPTIONS}")
	fi

	if [ -n "${KEY_FILE}" ] && [ -f "${KEY_FILE}" ]; then
		cmd+=("-u" "${KEY_FILE}")
	fi

	if [ -n "${SBK_KEY}" ] && [ -f "${SBK_KEY}" ]; then
		cmd+=("-v" "${SBK_KEY}")
	fi

	[ "${sparse_mode}" = "1" ] && cmd+=("--sparse")
    cmd+=("${target_board}" "${target_rootdev}")

    "${cmd[@]}"
}

function get_disk_name
{
	local ext_dev="${1}"
	local disk=
	# ${ext_dev} could be specified as a partition; therefore, removing the
	# number if external storage device is scsi, otherwise, remove the trailing
	# "p[some number]" here
	if [[ "${ext_dev}" = sd* ]]; then
		disk=${ext_dev%%[0-9]*}
	else
		disk="${ext_dev%p*}"
	fi
	echo "${disk}"
}

build_working_dir()
{

	local device_instance=${1}
	DEST_FOLDER=${LINUX_BASE_DIR}/temp_initrdflash

	mkdir -p "${DEST_FOLDER}"

	TEMP_INITRD_FLASH_DIR="${DEST_FOLDER}/bootloader${device_instance}"

	if [ -z "${reuse}" ]; then
		echo "Create flash environment ${device_instance}"

		rsync -avrxx --exclude="system*.img" --exclude="system*.raw" \
		--exclude="system*.img_ext" --exclude="system*.raw_ext" \
		--exclude="system*.img_b" \
		 "${BOOTLOADER_DIR}/" "${TEMP_INITRD_FLASH_DIR}/"


		echo "Finish creating flash environment ${device_instance}."
	else
		echo "Reuse flash environment ${device_instance}"
	fi

}

generate_rcm_bootcmd()
{
	if [ -z "${BOARDID}" ]; then
		# Extract BOARDID, FAB, BOARDSKU, BOARDREV from cvm.bin so we don't
		# have to ask the target again.
		BOARDID=$(sudo "${BOOTLOADER_DIR}/chkbdinfo" -i "${BOOTLOADER_DIR}/cvm.bin" | xargs);
		export BOARDID
		FAB=$(sudo "${BOOTLOADER_DIR}/chkbdinfo" -f "${BOOTLOADER_DIR}/cvm.bin" | xargs);
		export FAB
		BOARDSKU=$(sudo "${BOOTLOADER_DIR}/chkbdinfo" -k "${BOOTLOADER_DIR}/cvm.bin" | xargs);
		export BOARDSKU
		BOARDREV=$(sudo "${BOOTLOADER_DIR}/chkbdinfo" -r "${BOOTLOADER_DIR}/cvm.bin" | xargs);
		export BOARDREV
	fi

	local cmd
	local cmdarg=

	if [ -n "${KEY_FILE}" ] && [ -f "${KEY_FILE}" ]; then
		cmdarg+="-u \"${KEY_FILE}\" "
	fi

	if [ -n "${SBK_KEY}" ] && [ -f "${SBK_KEY}" ]; then
		cmdarg+="-v \"${SBK_KEY}\" "
	fi

	cmd="${LINUX_BASE_DIR}/flash.sh ${cmdarg} --no-flash --rcm-boot ${target_board} mmcblk0p1"
	echo "${cmd}"
	eval "${cmd}"

	cmd=()

	if [ -n "${KEY_FILE}" ] && [ -f "${KEY_FILE}" ]; then
		cmd+=("-u" "\"${KEY_FILE}\"")
	fi

	if [ -n "${external_device}" ]; then
		cmd+=("--external-device" \
		"${external_device}" "-c" "\"${config_file}\"")
		if [ -n "${external_size}" ]; then
			cmd+=("-S" "${external_size}")
		fi
	fi

	if [ -n "${external_only}" ]; then
		cmd+=("${external_only}")
	fi

	if [ -n "${target_partname}" ]; then
		cmd+=("-k" "${target_partname}")
	fi

	if [ -n "${initrd_only}" ]; then
		cmd+=("--initrd")
	fi

	echo "${cmd[*]} ${target_board} ${target_rootdev}" > "${L4T_INITRD_FLASH_DIR}/${INITRD_FLASHPARAM}"
	echo "Save initrd flashing command parameters to ${L4T_INITRD_FLASH_DIR}/${INITRD_FLASHPARAM}"
}

ping_device()
{
	while IFS=  read -r; do
		netpath=/sys/class/net/${REPLY}
		netserialnumber=$(udevadm info --query=property "${netpath}" | sed -n 's/^ID_SERIAL_SHORT=\(.*\)/\1/p')
		if [ "${netserialnumber}" = "${serialnumber}" ]; then
			echo "${REPLY}" > "${sshcon}"
		fi
	done < <(nmcli con show --active | grep nvidia-flash | awk '{print $4}')

	if [ -z "$(cat "${sshcon}")" ]; then
		return 1
	fi
	if ! ping6 -c 1 "fe80::1%$(cat "${sshcon}")" > /dev/null 2>&1;
	then
		return 1
	fi
	return 0
}

run_commmand_on_target()
{
	echo "Run command: ${2} on root@fe80::1%${1}"
	sshpass -p root ssh -q -oServerAliveInterval=15 -oServerAliveCountMax=3 -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -6 "root@fe80::1%${1}" "$2";
}

copy_qspi_flash_packages()
{
	if ! grep -qE "^[0-9]+, 3:0" "${NFS_IMAGES_DIR}/flash.idx"; then
		return
	fi
	mkdir -p "${working_dir}/initrd/qspi"

	for i in $(grep -E "^[0-9]+, 3:0" "${NFS_IMAGES_DIR}/flash.idx" | awk -F", " '{print $5}' | uniq | grep -v "^$");
	do
		cp "${NFS_IMAGES_DIR}/${i}" "${working_dir}/initrd/qspi"
	done

	cp "${NFS_IMAGES_DIR}/flash.idx" "${working_dir}/initrd/qspi"
	cp "${NFS_IMAGES_DIR}/flash.cfg" "${working_dir}/initrd/qspi"
	cp "${NFS_IMAGES_DIR}/${KERNEL_FLASH_SCRIPT}" "${working_dir}/initrd/qspi"
}

generate_flash_initrd()
{
	local dev_instance="$1"

	pushd "${working_dir}"

	abootimg -x "${BOOTLOADER_DIR}/recovery.img"

	mkdir -p "${working_dir}/initrd"

	pushd "${working_dir}/initrd"

	gunzip -c "${working_dir}/initrd.img" | cpio -i

	cp "${INITRDDIR_L4T_DIR}/nv_enable_remote.sh" \
		"${working_dir}/initrd/bin"
	cp "${INITRDDIR_L4T_DIR}/nv_recovery.sh" "${working_dir}/initrd/bin"
	cp "${ROOTFS_DIR}/usr/sbin/flash_erase" "${working_dir}/initrd/usr/sbin"
	cp "${ROOTFS_DIR}/usr/sbin/mtd_debug" "${working_dir}/initrd/usr/sbin"
	cp "${ROOTFS_DIR}/sbin/blkdiscard" "${working_dir}/initrd/sbin"
	cp "${ROOTFS_DIR}/sbin/partprobe" "${working_dir}/initrd/sbin"
	cp "${ROOTFS_DIR}/bin/mktemp" "${working_dir}/initrd/bin"
	cp "${ROOTFS_DIR}/lib/aarch64-linux-gnu/libsmartcols.so.1" "${working_dir}/initrd/lib/aarch64-linux-gnu"

	if [ -n "${external_device}" ]; then
		echo "external_device=/dev/$(get_disk_name "${external_device}")" >> "${working_dir}/initrd/initrd_flash.cfg"
	fi
	if [ -n "${erase_all}" ]; then
		echo "erase_all=1" >> "${working_dir}/initrd/initrd_flash.cfg"
	fi
	echo "instance=${dev_instance}" >> "${working_dir}/initrd/initrd_flash.cfg"

	# Prepare for QSPI image flashing in initrd if neccessary
	if [ -z "${external_only}" ]; then
		copy_qspi_flash_packages
	fi

	find . | cpio -H newc -o | gzip -9 -n > "${working_dir}/initrd.img"

	popd

	cmdline=$(sed 's/^cmdline = //p' "${working_dir}/bootimg.cfg")
	"${BOOTLOADER_DIR}/mkbootimg" --kernel "${working_dir}/zImage" \
		--ramdisk "${working_dir}/initrd.img" --cmdline "${cmdline}" \
		-o "${BOOTLOADER_DIR}/boot${dev_instance}.img"

	OUTPUT_FILE="${BOOTLOADER_DIR}/boot${dev_instance}.img"

	sign_bootimg

	echo "flashimg${dev_instance}=${OUTPUT_FILE}" | tee -a "${L4T_INITRD_FLASH_DIR}/${FLASH_IMG_MAP}"

	popd

}

sign_bootimg()
{
	set +u
	if [ "${CHIPID}" = "0x18" ] && [ -n "${KEY_FILE}" ] && [ -f "${KEY_FILE}" ]; then
		OUTPUT_FILE=$("${LINUX_BASE_DIR}"/l4t_sign_image.sh \
					--file "${OUTPUT_FILE}" \
					--key "${KEY_FILE}" --chip "${CHIPID}" -q --split "False");
	fi
	set -u
}

wait_for_booting()
{
	ext=""
	mmcblk0=""
	mmcblk0boot0=""
	mmcblk0boot1=""
	maxcount=${timeout:-60}
	count=0
	device_instance=$1
	while true
	do
		if ls /dev/sd* 1> /dev/null 2>&1; then
			while IFS=  read -r -d $'\0'; do
				path="$(readlink -f "$REPLY")"
				! [ -b "${path}" ] && continue
				properties=$(flock -w 60 /var/lock/nvidiainitrdflash udevadm info --query=property "$path")
				dev=$(echo "${properties}" | sed -n 's/^ID_VENDOR=\(.*\)/\1/p')
				model=$(echo "${properties}" | sed -n 's/^ID_MODEL=\(.*\)/\1/p')
				model_id=$(echo "${properties}" | sed -n 's/^ID_MODEL_ID=\(.*\)/\1/p')
				vendor_id=$(echo "${properties}" | sed -n 's/^ID_VENDOR_ID=\(.*\)/\1/p')

				if [ "${model_id}" != "7035" ] || [ "${vendor_id}" != "0955" ]; then
					continue
				fi

				if ! echo "${model}" | grep -q "${device_instance}"; then
					continue
				fi
				if [ "${dev}" = "mmc0" ]; then
					mmcblk0=$(basename "${path}")
				elif [ "${dev}" = "ext0" ]; then
					ext=$(basename "${path}")
				elif [ "${dev}" = "mmc0b0" ]; then
					mmcblk0boot0=$(basename "${path}")
				elif [ "${dev}" = "mmc0b1" ]; then
					mmcblk0boot1=$(basename "${path}")
				fi

			done < <(find /dev/ -maxdepth 1 -not -name "*[0-9]" -name "sd*" -print0)

			# If external device is not given from parameters, we only look for
			# /dev/mmcblk0, /dev/mmcblk0boot0, and /dev/mmcblk0boot1
			#
			# If external device is defined, then we also look for the external
			# device node file
			#
			# If we only flash external device, then we only need the
			# external device node file
			if [ -z "${external_device}" ] && [ -n "${mmcblk0}" ] && [ -n "${mmcblk0boot0}" ] && [ -n "${mmcblk0boot1}" ]; then
				serialnumber=$(flock -w 60 /var/lock/nvidiainitrdflash udevadm info --query=property "/dev/${mmcblk0}" | sed -n 's/^ID_SERIAL_SHORT=\(.*\)/\1/p')
				break
			elif [ -n "${ext}" ] && [ -n "${mmcblk0}" ] && [ -n "${mmcblk0boot0}" ] && [ -n "${mmcblk0boot1}" ]; then
				serialnumber=$(flock -w 60 /var/lock/nvidiainitrdflash udevadm info --query=property "/dev/${mmcblk0}" | sed -n 's/^ID_SERIAL_SHORT=\(.*\)/\1/p')
				break
			elif [ -n "${external_only}" ] && [ -n "${ext}" ]; then
				serialnumber=$(flock -w 60 /var/lock/nvidiainitrdflash udevadm info --query=property "/dev/${ext}" | sed -n 's/^ID_SERIAL_SHORT=\(.*\)/\1/p')
				break
			fi

		fi
		echo "Waiting for target to boot-up..."
		sleep 1;
		count=$((count + 1))
		if [ "${count}" -ge "${maxcount}" ]; then
			echo "Timeout"
			exit 1
		fi

	done
}

wait_for_ssh()
{

	printf "%s" "Waiting for device to expose ssh ..."
	count=0
	while ! ping_device
	do
		printf "..."
		count=$((count + 1))
		if [ "${count}" -ge "${maxcount}" ]; then
			echo "Timeout"
			exit 1
		fi
		sleep 1
	done
}



flash()
{
	local cmd=()

	if [ -n "${target_partname}" ]; then
		cmd+=("-k" "${target_partname}")
	fi

	if [ -n "${external_only}" ]; then
		cmd+=("${external_only}")
	fi

	MMCBLK0="${mmcblk0}" MMCBLKB0="${mmcblk0boot0}" MMCBLKB1="${mmcblk0boot1}"  \
	EXTDEV_ON_HOST="${ext}" EXTDEV_ON_TARGET="$(get_disk_name "${external_device}")" \
	TARGET_IP="$(cat "${sshcon}")" "${NFS_IMAGES_DIR}/${KERNEL_FLASH_SCRIPT}" --host-mode "${cmd[@]}"
}

flash_qspi()
{
	if [ -z "${external_only}" ]; then
		if [ -n "${target_partname}" ]; then
			cmd+=("-k" "${target_partname}")
		fi
		run_commmand_on_target "$(cat "${sshcon}")" "if [ -f /qspi/${KERNEL_FLASH_SCRIPT} ]; then USER=root /qspi/${KERNEL_FLASH_SCRIPT} --no-reboot --qspi-only ${cmd[*]}; fi"
	fi
}

boot_initrd()
{
	local usb_instance=${1}
	local skipuid=${2}
	local dev_instance=${3}

	pushd "${TEMP_INITRD_FLASH_DIR}"
	local cmd
	if [ -n "${usb_instance}" ]; then
		local var=flashimg${dev_instance}
		cmd="$(sed -e "s/$/ --instance ${usb_instance}/" \
			-e "s/kernel [a-zA-Z0-9._\-]*/kernel $(basename "${!var}")/" "${TEMP_INITRD_FLASH_DIR}/flashcmd.txt")"
	fi
	if [ -n "${skipuid}" ]; then
		cmd+=" --skipuid"
	fi
	echo "${cmd}"
	eval "${cmd}"

	popd
}

package()
{
    local workdir="${1}"
    local cmdline="${2}"
    local tid="${3}"
	local temp_bootloader="${workdir}/bootloader"
	mkdir -p "${temp_bootloader}"
	pushd "${BOOTLOADER_DIR}"
    cp tegrabct_v2 "${temp_bootloader}";
    cp tegradevflash_v2 "${temp_bootloader}";
    cp tegraflash_internal.py "${temp_bootloader}";
    cp tegrahost_v2 "${temp_bootloader}";
    cp tegraparser_v2 "${temp_bootloader}";
    cp tegrarcm_v2 "${temp_bootloader}";
    cp tegrasign_v3*.py "${temp_bootloader}";
    cp tegraopenssl "${temp_bootloader}";
    if [ "${tid}" = "0x19" ]; then
        cp sw_memcfg_overlay.pl "${temp_bootloader}";
    fi;


    # Parsing the command line of tegraflash.py, to get all files that tegraflash.py and
    # tegraflash_internal.py needs so copy them to the working directory.
    cmdline=$(echo "${cmdline}" | sed -e s/\;/\ /g -e s/\"//g);
    read -r -a opts <<< "${cmdline}"
    optnum=${#opts[@]};
    for (( i=0; i < optnum; )); do
        opt="${opts[$i]}";
        opt=${opt//\,/\ }
        read -r -a files <<< "${opt}"
        filenum=${#files[@]};
        for (( j=0; j < filenum; )); do
            file="${files[$j]}";
            if [ -f "${file}" ]; then
                folder=$(dirname "${file}");
                if [ "${folder}" != "." ]; then
                    mkdir -p "${temp_bootloader}/${folder}";
                fi;
                cp "${file}" "${temp_bootloader}/${folder}";
            fi;
            j=$((j+1));
        done;
        i=$((i+1));
    done;
	cp flashcmd.txt "${temp_bootloader}";
	awk -F= '{print $2}' "${L4T_INITRD_FLASH_DIR}/${FLASH_IMG_MAP}" | xargs cp -t "${temp_bootloader}"
	popd

	local temp_kernelflash="${workdir}/tools/kernel_flash"
	mkdir -p "${temp_kernelflash}"
	cp -a "${L4T_INITRD_FLASH_DIR}"/* "${temp_kernelflash}"
	cp "${LINUX_BASE_DIR}/${target_board}.conf" "${workdir}/"
	cp "${LINUX_BASE_DIR}/"*.common "${workdir}/"

}

external_device=""
qspi=""
config_file=""
external_size=""
external_only=""
no_flash="0"
sparse_mode="0"
sshcon="$(mktemp)"
usb_instance=""
flash_only=0
OPTIONS=""
KEY_FILE=""
erase_all=""
device_instance="0"
target_partname=""
max_massflash=""
massflash_mode=""
SBK_KEY=""
keep=""
reuse=""
timeout=""
skipuid=""
initrd_only=""

source "${L4T_INITRD_FLASH_DIR}"/l4t_initrd_flash.func
parse_param "$@"

check_prerequisite

get_max_flash

if [ "${flash_only}" = "0" ]; then
cat <<EOF
************************************
*                                  *
*  Step ${initrd_flash_step}: Generate flash packages *
*                                  *
************************************
EOF
	generate_flash_package

	((initrd_flash_step+=1))
cat <<EOF
******************************************
*                                        *
*  Step ${initrd_flash_step}: Generate rcm boot commandline *
*                                        *
******************************************
EOF
	generate_rcm_bootcmd

	rm -f "${L4T_INITRD_FLASH_DIR}/${FLASH_IMG_MAP}"

	for i in $(seq 0 "$((max_massflash - 1))")
	do
		generate_flash_initrd "${i}"
	done

	((initrd_flash_step+=1))
	if [ "${massflash_mode}" = "1" ]; then
		mkdir -p "${working_dir}/mfi_${target_board}/"
		package "${working_dir}/mfi_${target_board}/" "$(cat "${BOOTLOADER_DIR}/flashcmd.txt")" "${CHIPID}"
		tar -zcvf "${LINUX_BASE_DIR}/mfi_${target_board}.tar.gz" -C "${working_dir}" "./mfi_${target_board}"
		echo "Massflash package is generated at ${LINUX_BASE_DIR}/mfi_${target_board}.tar.gz"
	fi

fi




if [ "${no_flash}" = "0" ]; then


cat <<EOF
**********************************************
*                                            *
*  Step ${initrd_flash_step}: Build the flashing environment    *
*                                            *
**********************************************
EOF

	source "${L4T_INITRD_FLASH_DIR}/${FLASH_IMG_MAP}"

	build_working_dir "${device_instance}"
	((initrd_flash_step+=1))

cat <<EOF
****************************************************
*                                                  *
*  Step ${initrd_flash_step}: Boot the device with flash initrd image *
*                                                  *
****************************************************
EOF
	((initrd_flash_step+=1))

	boot_initrd "${usb_instance}" "${skipuid}" "${device_instance}"


cat <<EOF
***************************************
*                                     *
*  Step ${initrd_flash_step}: Start the flashing process *
*                                     *
***************************************
EOF

	wait_for_booting "${device_instance}"

	wait_for_ssh

	if [ -n "${initrd_only}" ]; then
		echo "Device has booted into initrd. You can ssh to the target by the command:"
		echo "$ ssh root@fe80::1%$(cat "${sshcon}")"
		exit
	fi

	flash_qspi &
	qspi=$!

	flash

	if ! wait "${qspi}"; then
		echo "Error flashing qspi"
		exit 1
	fi
	echo ""
	echo "Note: The flash process might have added some nvidia-flash-* connections in
NetworkManager to set up USB ethernet through flashing port (L4t USB Device mode).
You might want to check your NetworkManager configuration if you have some special
configuration."
	echo "Reboot target"
	if ! run_commmand_on_target "$(cat "${sshcon}")" "sync; { sleep 1; reboot; } >/dev/null &"; then
		echo "Reboot failed."
		if [ -f "/dev/${mmcblk0}" ]; then
				rm "/dev/${mmcblk0}"
		fi
		if [ -f "/dev/${mmcblk0}" ]; then
				rm "/dev/${mmcblk0boot0}"
		fi
		if [ -f "/dev/${mmcblk0}" ]; then
				rm "/dev/${mmcblk0}"
		fi
		if [ -f "/dev/${mmcblk0}" ]; then
				rm "/dev/${mmcblk0}"
		fi
		exit 1
	fi
fi

echo "Success"
