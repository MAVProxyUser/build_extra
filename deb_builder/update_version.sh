#!/bin/bash

HOMEPATH=$(pwd)
ATHENA_CONFIG=/home/builder/athena/config
ATHENA_DEBPATH=/athena_deb_repos
MODULE_VERSION=${ATHENA_CONFIG}/module_version.txt
checksum=0
kernel_deb_version=""
VERSION_OFFSET=1
CHECKSUM_OFFSET=2
FRI_VERSION_OFFSET=0
SEC_VERSION_OFFSET=1
THR_VERSION_OFFSET=2

athena_version_update() {
	sed -i 's/Version: .*/Version: '${BUILD_REL_VERSION}'/' ${ATHENA_DEBPATH}/athena_version_deb/src/DEBIAN/control
}

#"athena_code_check athena_ros2", "athena_ros2" should be the directory of source code located in root directory "/".
#(or soft link to dir of source code^^)
athena_code_check(){
found=0
checksum=0
if [ ! -d /$1 ]; then
	echo "could not find the /$1 dir"
	exit 1
fi
dir_arr=$(find /$1/ -name .git -type d -print;)
for dir in ${dir_arr[*]}
do
	cd /${dir}
	commitid=$(git log -1 --pretty=format:"%h")
	commitid=$((16#${commitid}))
	checksum=$((${commitid} + ${checksum}))
done

if [ $1 == "athena_ros2" ]; then
	cd ${ATHENA_DEBPATH}/athena_ros2_deb
	tempid=$(git log -1 --pretty=format:"%h")
	tempid=$((16#${tempid}))
	checksum=$((${tempid} + ${checksum}))
fi

checksum=$(printf "%x" ${checksum})
checksum=${checksum:0:6}
echo "found /$1 checksum value is $checksum"

str=$(cat ${MODULE_VERSION})

str_arr=(${str//;/ })
for s in ${str_arr[@]}
do
	unit_arr=(${s//,/ })
	for u in ${unit_arr[@]}
	do
		if [ $u == module:$1 ]
		then
			version_arr=(${unit_arr[VERSION_OFFSET]//./ })
			tmp_version=(${version_arr[FRI_VERSION_OFFSET]//:/ })
			fri_version=${tmp_version[1]}
			sec_version=${version_arr[SEC_VERSION_OFFSET]}
			thr_version=${version_arr[THR_VERSION_OFFSET]}
			if [ "checksum:${checksum}" == ${unit_arr[CHECKSUM_OFFSET]} ]
			then
				echo "project $u checksum is found, do not upgrade"
				echo "deb version frist:${fri_version}, second:${sec_version},thr_version:"${thr_version}
				if [ $1 == "athena_kernel" ]; then
					kernel_deb_version=${fri_version}.${sec_version}.${thr_version}
					echo "kernel_deb_version is ${kernel_deb_version}"
				else
					sed -i 's/Version: .*/Version: '${fri_version}.${sec_version}.${thr_version}'/' ${ATHENA_DEBPATH}/$1_deb/src/DEBIAN/control
				fi
				found=1
				break;
			else
				thr_version=$((${thr_version}+1))
				echo "deb version frist:${fri_version}, second:${sec_version},thr_version:"${thr_version}
				if [ $1 == "athena_kernel" ]; then
					kernel_deb_version=${fri_version}.${sec_version}.${thr_version}
					echo "kernel_deb_version is ${kernel_deb_version}"
				else
					sed -i 's/Version: .*/Version: '${fri_version}.${sec_version}.${thr_version}'/' ${ATHENA_DEBPATH}/$1_deb/src/DEBIAN/control
				fi

				echo "old u:$u ${unit_arr[CHECKSUM_OFFSET]} by checksum:${checksum}"
				sed -i '/'"$u"'/ {s/'"${unit_arr[CHECKSUM_OFFSET]}"'/'"checksum:${checksum}"'/g}' ${MODULE_VERSION}
				sed -i '/'"$u"'/ {s/'"${unit_arr[VERSION_OFFSET]}"'/'"version:${fri_version}.${sec_version}.${thr_version}"'/g}' ${MODULE_VERSION}
			fi
		fi
	done
	if [ $found == "1" ]; then
		break;
	fi
done
}

cat ${MODULE_VERSION}
if [ "$1""x" = "ROSx" ]
then
	athena_code_check athena_ros2
else
	athena_version_update
	athena_code_check athena_ros2
	athena_code_check athena_sensor
	athena_code_check athena_sys_config
	export ENV_KERNEL_DEB_VERSION=${kernel_deb_version}
fi
cat ${MODULE_VERSION}

