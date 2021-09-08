#!/bin/bash
#
set -e
source /athena_deb_repos/update_version.sh
CUR_DIR=$(pwd)
BSPPATH=/l4t_bsp
ATHENA_DEBPATH=/athena_deb_repos
target=$1
rootfs_dev=$2
KERNEL_DEB_VERSION="1.0.32" #default kernel debs version
NV_BASE_VERSION="32.5.0-20210115151051"
KERNEL_CODE_VERSION="4.9.201"

KSRC_DIR=/athena_kernel/kernel # kernel source code folder
KOUT_DIR=${KSRC_DIR}/kernel-4.9/okernel # kernel build output folder

if [ -z ${ENV_KERNEL_DEB_VERSION} ]; then
	echo "'ENV_KERNEL_DEB_VERSION' is not set, use default kernel deb version(${KERNEL_DEB_VERSION}), plz check the build script !"
else
	KERNEL_DEB_VERSION=${ENV_KERNEL_DEB_VERSION}
fi
echo "KERNEL_DEB_VERSION is ${KERNEL_DEB_VERSION} !"
#make dobot-bootloader deb(bl+kernel+dtb partitions)++++++++++++++++++++++++
echo "make bl update payload...."
cd ${BSPPATH}
./build_l4t_bup.sh ${target} ${rootfs_dev}
${BSPPATH}/tools/Debian/nvdebrepack.sh -i ${BSPPATH}/bootloader/payloads_t19x/bl_update_payload:/opt/ota_package/t19x/bl_update_payload \
		-i ${BSPPATH}/bootloader/payloads_t19x/bl_only_payload:/opt/ota_package/t19x/bl_only_payload \
		-n "Qiu Wenguang <qiuwenguang@xiaomi.com>" \
		-v ${KERNEL_DEB_VERSION} \
		${BSPPATH}/bootloader/dobot-bootloader_*.deb

cp ${BSPPATH}/tools/Debian/dobot-bootloader_*.deb ${ATHENA_DEBPATH}/debs/
echo "done!"
#make dobot-bootloader deb(bl+kernel+dtb partitions)--------------------------

########################################################################################################################################

rm -rf ${ATHENA_DEBPATH}/dobot_kernel_modules_deb
rm -rf ${ATHENA_DEBPATH}/dobot_kernel_headers_deb
#make dobot-kernel-modules deb++++++++++++++++++++++++
echo "Prepare to make dobot-kernel-modules deb based on dobot-kernel_*.deb..."
find ${BSPPATH}/kernel/ -name "dobot-kernel-modules_*.deb" -exec cp {} ${ATHENA_DEBPATH}/debs/ \;
mkdir -p ${ATHENA_DEBPATH}/dobot_kernel_modules_deb/src/DEBIAN
dpkg -X ${ATHENA_DEBPATH}/debs/dobot-kernel-modules_*.deb ${ATHENA_DEBPATH}/dobot_kernel_modules_deb/src
dpkg -e ${ATHENA_DEBPATH}/debs/dobot-kernel-modules_*.deb ${ATHENA_DEBPATH}/dobot_kernel_modules_deb/src/DEBIAN
sed -i 's/Package: .*/Package: dobot-kernel-modules/' ${ATHENA_DEBPATH}/dobot_kernel_modules_deb/src/DEBIAN/control
rm -f ${ATHENA_DEBPATH}/debs/dobot-kernel-modules_*.deb

#delete kernel only payload and /boot/Image, because kernel is included in dobot-bootloader
rm -rf ${ATHENA_DEBPATH}/dobot_kernel_modules_deb/src/opt
rm -rf ${ATHENA_DEBPATH}/dobot_kernel_modules_deb/src/boot

#delete old ko files and modules files
rm -rf ${ATHENA_DEBPATH}/dobot_kernel_modules_deb/src/lib/modules/4.9.201-tegra/kernel/*
rm -rf ${ATHENA_DEBPATH}/dobot_kernel_modules_deb/src/lib/modules/4.9.201-tegra/modules.*
#rename 
#mv ${ATHENA_DEBPATH}/dobot_kernel_modules_deb/src/usr/share/doc/nvidia-l4t-kernel ${ATHENA_DEBPATH}/dobot_kernel_modules_deb/src/usr/share/doc/dobot-kernel-modules

#make a temporary fake deb !!!
dpkg -b ${ATHENA_DEBPATH}/dobot_kernel_modules_deb/src/ ${ATHENA_DEBPATH}/debs

#collect .ko files
cd $KOUT_DIR
find ./ -regex ".*\.ko" | xargs -i cp --parents -rf {} ${ATHENA_DEBPATH}/dobot_kernel_modules_deb/src/lib/modules/4.9.201-tegra/kernel/
ls ./ |grep "modules." | xargs -i cp -f {} ${ATHENA_DEBPATH}/dobot_kernel_modules_deb/src/lib/modules/4.9.201-tegra/

#remove debug info to shrink the size
echo "remove debug info of ko files to shrink the size~"
find ${ATHENA_DEBPATH}/dobot_kernel_modules_deb/src/lib/modules/4.9.201-tegra/kernel/ -regex ".*\.ko" | xargs -i ${CROSS_COMPILE}strip --strip-debug {}

#make dobot-kernel-modules deb--------------------------

########################################################################################################################################

#make dobot-kernel-headers deb++++++++++++++++++++++++
echo "Prepare to make dobot-kernel-headers deb..."
find ${BSPPATH}/kernel/ -name "dobot-kernel-headers_*.deb" -exec cp {} ${ATHENA_DEBPATH}/debs/ \;
mkdir -p ${ATHENA_DEBPATH}/dobot_kernel_headers_deb/src/DEBIAN
dpkg -X ${ATHENA_DEBPATH}/debs/dobot-kernel-headers_*.deb ${ATHENA_DEBPATH}/dobot_kernel_headers_deb/src
dpkg -e ${ATHENA_DEBPATH}/debs/dobot-kernel-headers_*.deb ${ATHENA_DEBPATH}/dobot_kernel_headers_deb/src/DEBIAN
sed -i 's/doboot/dobot/' ${ATHENA_DEBPATH}/dobot_kernel_headers_deb/src/DEBIAN/control
sed -i 's/tegra-//' ${ATHENA_DEBPATH}/dobot_kernel_headers_deb/src/DEBIAN/control
rm -f ${ATHENA_DEBPATH}/debs/dobot-kernel-headers_*.deb

#delete old header files files
rm -rf ${ATHENA_DEBPATH}/dobot_kernel_headers_deb/src/usr/src/linux-headers-4.9.201-tegra-ubuntu18.04_aarch64/*
#rename 
#mv ${ATHENA_DEBPATH}/dobot_kernel_headers_deb/src/usr/share/doc/nvidia-l4t-kernel-headers ${ATHENA_DEBPATH}/dobot_kernel_headers_deb/src/usr/share/doc/dobot-kernel-headers

#make a temporary fake deb !!!
dpkg -b ${ATHENA_DEBPATH}/dobot_kernel_headers_deb/src/ ${ATHENA_DEBPATH}/debs

WORK_DIR=${ATHENA_DEBPATH}/dobot_kernel_headers_deb/src/usr/src/linux-headers-4.9.201-tegra-ubuntu18.04_aarch64 # target folder

cd $KSRC_DIR
find ./kernel-4.9 -regex ".*Makefile.*\|.*Kconfig.*\|.*Kbuild.*\|.*\.bc\|.*\.lds\|.*\.pl\|.*\.sh" | xargs -i cp --parents -rf {} $WORK_DIR
cp --parents -rf ./kernel-4.9/arch/arm/include ./kernel-4.9/arch/arm64/include ./kernel-4.9/scripts ./kernel-4.9/security/selinux/include ./kernel-4.9/include ./nvgpu/include ./nvidia/include $WORK_DIR

cd $KOUT_DIR
cp -f .config $WORK_DIR/kernel-4.9/
cp -f kernel/bounds.s $WORK_DIR/kernel-4.9/kernel/
cp -f arch/arm64/kernel/asm-offsets.s $WORK_DIR/kernel-4.9/arch/arm64/kernel/
cp -f Module.symvers $WORK_DIR/kernel-4.9/
cp -rf ./include/* $WORK_DIR/kernel-4.9/include
cp -rf ./arch/arm64/include/generated $WORK_DIR/kernel-4.9/arch/arm64/include/
cd ${CUR_DIR}
#make dobot-kernel-headers deb--------------------------


echo "==========Re-pack dobot-kernel-headers and dobot-kernel-modules !=========="
# delete "	-d "dobot-bootloader=${NV_BASE_VERSION}+${KERNEL_DEB_VERSION}" "
${BSPPATH}/tools/Debian/nvdebrepack.sh \
	-D ${ATHENA_DEBPATH}/dobot_kernel_modules_deb/src/lib/modules/4.9.201-tegra:/lib/modules/4.9.201-tegra \
	-n "Qiu Wenguang <qiuwenguang@xiaomi.com>" \
	-v ${KERNEL_DEB_VERSION} \
	${ATHENA_DEBPATH}/debs/dobot-kernel-modules_*.deb

${BSPPATH}/tools/Debian/nvdebrepack.sh \
	-D ${ATHENA_DEBPATH}/dobot_kernel_headers_deb/src/usr/src/linux-headers-4.9.201-tegra-ubuntu18.04_aarch64:/usr/src/linux-headers-4.9.201-tegra-ubuntu18.04_aarch64 \
	-n "Qiu Wenguang <qiuwenguang@xiaomi.com>" \
	-v ${KERNEL_DEB_VERSION} \
	${ATHENA_DEBPATH}/debs/dobot-kernel-headers_*.deb

#delete fake debs
rm -f ${ATHENA_DEBPATH}/debs/dobot-kernel-headers_${KERNEL_CODE_VERSION}-${NV_BASE_VERSION}_arm64.deb
rm -f ${ATHENA_DEBPATH}/debs/dobot-kernel-modules_${KERNEL_CODE_VERSION}-${NV_BASE_VERSION}_arm64.deb

cp ${BSPPATH}/tools/Debian/dobot-kernel-headers_*.deb ${ATHENA_DEBPATH}/debs/
cp ${BSPPATH}/tools/Debian/dobot-kernel-modules_*.deb ${ATHENA_DEBPATH}/debs/

echo "Make dobot-bootloader, dobot-kernel-modules, dobot-kernel-headers done !"
