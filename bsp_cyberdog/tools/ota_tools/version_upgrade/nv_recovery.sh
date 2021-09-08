#!/bin/bash

# Copyright (c) 2019-2020, NVIDIA CORPORATION.  All rights reserved.
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

# This is a script to run tasks automatically in recovery mode
set -e

OTA_PACKAGE_MOUNTPOINT=/mnt
OTA_WORK_DIR=${OTA_PACKAGE_MOUNTPOINT}/ota_work
OTA_MAX_RETRY_COUNT=1
OTA_LOG_DIR=${OTA_PACKAGE_MOUNTPOINT}/ota_log
OTA_LOG_FILE=
BASE_VERSION="$(grep -oE "base_version=[A-Z0-9\-]+" < /proc/cmdline | head -n 1 | cut -d=  -f 2)"
TARGET_BOARD="$(grep -oE "target_board=[a-zA-Z0-9\-]+" < /proc/cmdline | head -n 1 | cut -d=  -f 2)"

source /bin/nv_ota_log.sh
source /bin/nv_ota_exception_handler.sh
source /bin/nv_ota_update.sh
source /bin/nv_ota_check_version.sh
source /bin/nv_ota_adjust_app.sh
source /bin/nv_ota_validate.sh

# Enable remote access through ssh
ota_log "enable_remote_access"
if ! enable_remote_access; then
	ota_log "Failed to run \"enable_remote_access\""
	reboot_system
fi

INTERNAL_DEVICE="/dev/mmcblk0p1"
found=0
# mount the SD card containing the ota package
: '
EXTERNAL_DEVICES=(
	"/dev/mmcblk1p1"
	"/dev/mmcblk2p1"
	"/dev/sda1"
	"/dev/sdb1"
)

sleep 10

for ext_dev in "${EXTERNAL_DEVICES[@]}"; do
	echo "Check device ${ext_dev}"
	if [ -e "${ext_dev}" ];then
		if ! mount "${ext_dev}" "${OTA_PACKAGE_MOUNTPOINT}"; then
			ota_log "Failed to mount ${ext_dev} to ${OTA_PACKAGE_MOUNTPOINT}"
			continue
		fi
		if [ ! -f "${OTA_PACKAGE_MOUNTPOINT}/${OTA_PACKAGE}" ];then
			ota_log "OTA package ${OTA_PACKAGE} is not found on ${ext_dev}"
			umount "${OTA_PACKAGE_MOUNTPOINT}"
			continue
		fi
		found=1
		break
	fi
done
'
set +e
if [ "${found}" != 1 ];then
#	ota_log "External storage device is not found, try internal storage device"

	# For upgrading R28.2 to R32 ToT, the APP partition needs to be aligned
	# to 4K at first
	if [ "${BASE_VERSION}" == "R28-2" ]; then
		ota_log "ota_align_app_part"
		if ! ota_align_app_part; then
			ota_log "Failed to run \"ota_align_app_part\""
			/bin/bash
		fi
	fi

	if ! mount "${INTERNAL_DEVICE}" "${OTA_PACKAGE_MOUNTPOINT}"; then
		ota_log "Failed to mount ${INTERNAL_DEVICE} to ${OTA_PACKAGE_MOUNTPOINT}"
		/bin/bash
	fi
fi
set -e

if [ ! -d "${OTA_WORK_DIR}" ];then
	mkdir "${OTA_WORK_DIR}"
fi

# initialize log
ota_log "init_ota_log ${OTA_LOG_DIR}"
if ! init_ota_log "${OTA_LOG_DIR}"; then
	ota_log "Failed to run \"init_ota_log ${OTA_PACKAGE_MOUNTPOINT}/ota_log\""
	exit 1
fi
OTA_LOG_FILE="$(get_ota_log_file)"
ota_log "OTA_LOG_FILE=${OTA_LOG_FILE}"

# initialize exception handler
ota_log "init_exception_handler ${OTA_PACKAGE_MOUNTPOINT} ${OTA_LOG_FILE} ${OTA_MAX_RETRY_COUNT}"
if ! init_exception_handler "${OTA_PACKAGE_MOUNTPOINT}" "${OTA_LOG_FILE}" "${OTA_MAX_RETRY_COUNT}"; then
	ota_log "Failed to run \"init_exception_handler ${OTA_PACKAGE_MOUNTPOINT} ${OTA_LOG_DIR} ${OTA_MAX_RETRY_COUNT}\""
	exit 1
fi

set -e

if [ ! -f "${OTA_WORK_DIR}/base_version" ]; then
	ota_log "The base version file is not found at ${OTA_WORK_DIR}/base_version"
	exit 1
else
	BASE_VERSION="$(cat "${OTA_WORK_DIR}/base_version")"
	if [ -z "${BASE_VERSION}" ]; then
		ota_log "The base version file ${OTA_WORK_DIR}/base_version is corrupted"
		exit 1
	fi
fi
if [ ! -f "${OTA_WORK_DIR}/board_name" ]; then
	ota_log "The board name file is not found at ${OTA_WORK_DIR}/board_name"
	exit 1
else
	TARGET_BOARD="$(cat "${OTA_WORK_DIR}/board_name")"
	if [ -z "${TARGET_BOARD}" ]; then
		ota_log "The board name file ${OTA_WORK_DIR}/board_name is corrupted"
		exit 1
	fi
fi

# validate the OTA payload
ota_log "ota_validate_payload ${OTA_WORK_DIR} ${TARGET_BOARD} ${BASE_VERSION}"
if ! ota_validate_payload "${OTA_WORK_DIR}" "${TARGET_BOARD}" "${BASE_VERSION}"; then
	ota_log "Failed to run \"ota_validate_payload ${OTA_WORK_DIR} ${TARGET_BOARD} ${BASE_VERSION}\""
	exit 1
fi

ota_log "ota_check_rollback ${OTA_WORK_DIR} ${TARGET_BOARD} ${BASE_VERSION}"
if ! ota_check_rollback "${OTA_WORK_DIR}" "${TARGET_BOARD}" "${BASE_VERSION}"; then
	ota_log "Failed to run \"ota_check_rollback ${OTA_WORK_DIR} ${TARGET_BOARD} ${BASE_VERSION}\""
	exit 1
fi

ota_log "do_ota_update ${OTA_WORK_DIR}"
if ! do_ota_update "${OTA_WORK_DIR}"; then
	ota_log "Failed to run \"do_ota_update ${OTA_WORK_DIR}\""
	exit 1
fi

clean_up
