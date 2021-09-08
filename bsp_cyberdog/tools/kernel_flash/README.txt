************************************************************************
                              Linux for Jetson
                               Flash from NFS (Network File system)
                                   README
************************************************************************
The NVIDIA Jetson Linux Package provides "flash_from_nfs" tools to flash
the Jetson devices from NFS root filesystem. This document describes detailed
procedure of "flashing from nfs".

=========================================================================

The scripts in this folder support flashing a Jetson device from its NFS
root filesystem. They are wrapper scripts around flash.sh.

REQUIREMENTS:
- These scripts are to be run on the host. You must have the BSP downloaded and
extracted.
(See more how to download and extract the BSP in the official documentation)
- You must prepare a functional NFS root filesystem on the host system that
the target can NFS boot into. You can run this command on your NFS root
filesystem (via aarch64 emulation using qemu and chroot or via the target)
to install the required dependencies:
    $ sudo apt install libxml2-utils simg2img # For Debian-based Linux

The scripts support the following six workflows.





Workflow 1: With device in recovery mode, generate image and rcm-boot to NFS
and flash

You should do the following steps:
1.   Put device in recovery mode.
2.   Generate a flash package with l4t_create_flash_image_in_nfs.sh using
the following commands:

$ cd Linux_for_Tegra
$ sudo ./tools/kernel_flash/l4t_create_flash_image_in_nfs.sh \
                [-p <OPTIONS>]
                -N <IPaddr>:<nfsroot> <board-name> <rootdev>

where
    <IPaddr>:<nfsroot> is the location of the NFS root to be used by the
    target to boot.

    <board-name> and <rootdev> are similar to the corresponding variables used
    in the flash.sh command. (See more details in the official documentation's
    board name table).

    <OPTIONS> is flash.sh command options. The parameters specified here are
    passed to flash.sh to generate images.

l4t_create_flash_image_in_nfs.sh generates the flash package and stores it in a
tarball named `nv_flash_from_nfs_image.tbz2` in `tools/kernel_flash/`. If the
current host is also the NFS root filesystem, the script automatically puts the
flash package into a folder named `images_to_flash` at the root of the specified
NFS filesystem. Then it automatically triggers the target to start rcm-boot to
boot into NFS. If it does not boot into NFS, you can follow the steps in
Workflow 3 to rcm-boot the device to NFS.

If the current host is not the NFS root filesystem, you need to extract
`nv_flash_from_nfs_image.tbz2` into your NFS root filesystem. Then you can
follow the steps in Workflow 3 to rcm-boot the device to NFS.

The flash package may have multiple folders if you generate the flash
package for more than one device. For examples, the flash package structure can
be:

$ /images_to_flash/jetson-agx-xavier-devkit
$ /images_to_flash/jetson-xavier-nx-devkit-emmc
$ /images_to_flash/jetson-xavier-nx-devkit

Each folder has the following files:
- Index file: Has the partitions, partition images' name and other
information that are neccessary for flashing
- Partition image files: All the neccessary images file that are neccessary for
flashing
- l4t_flash_from_kernel.sh: The script that flashes the images into their
corresponding partitions

3.   After step 2, your target may rcm-boot to NFS. If it does not boot to NFS
for whatever reason, you must rcm-boot the target to NFS by issuing the following
command:

$ cd Linux_for_Tegra
$ sudo ./tools/kernel_flash/l4t_create_flash_image_in_nfs.sh --flash-only \
                -N <IPaddr>:<nfsroot> <board-name> <rootdev>

where
    <IPaddr>:<nfsroot> is the location of the NFS root to be used by the
    target to boot.

    <board-name> and <rootdev> variables are similar to those that are used for
    flash.sh. (See more details in official documentation's board name table).


4.   Once the flash package is put in the NFS root filesystem, and the target is
rcm-booted into NFS (either automatically or manually), you can control the
device through a keyboard and monitor. Alternatively, you can launch the l4t
device mode terminal (if the prepared NFS root filesystem supports it) using
minicom:


$ sudo minicom -D /dev/ttyACMx

where
    ttyACMx is the device node exposed by your Jetson device. As there can be
    multiple Jetson devices connected to your computer, there can be multiple
    ttyACM device nodes: ttyACM0, ttyACM1, ttyACM2, corresponding to the number
    of devices connected to your computer. Replace ttyACMx with the device node
    that you want to control.

Once you have access to the device terminal, you can run the following command
on the target's NFS to flash target device:

$ sudo ${flash_package_location}/images_to_flash/${board_name}/l4t_flash_from_kernel.sh

where
    ${flash_package_location} is the location of the flash package.
    ${board-name} is the same board name used when creating.

The above flash command can also be automatically triggered by systemd after
device boots into NFS. See the sample nv-l4t-flash-from-nfs.service for more
details.





Workflow 2: Generate flash package offline, then flash it at another time

1.   Generate a flash package without actually flashing by using the following
commands:


$ cd Linux_for_Tegra
$ sudo BOARDID=<BOARDID> FAB=<FAB> BOARDSKU=<BOARDSKU> BOARDREV=<BOARDREV> \
./tools/kernel_flash/l4t_create_flash_image_in_nfs.sh --no-flash -N \
<IPaddr>:<nfsroot> <board-name> <rootdev>

where
    <IPaddr>:<nfsroot> is the location of the NFS root to be used by the
    target to boot.

    <board-name> and <rootdev> variables are similar to those that are used for
    flash.sh. (See more details in official documentation's board name table).


l4t_create_flash_image_in_nfs.sh generates the flash package and stores it in a
tarball named `nv_flash_from_nfs_image.tbz2` in `tools/kernel_flash/`. If the
current host is also the NFS root filesystem, the script automatically puts the
flash package into a folder named `images_to_flash` at the root of the specified
NFS filesystem.

2.   Once the flash package is present in the NFS, you can flash the device
(see workflow 3) using the pregenerated image without having to generate the
images again.






Workflow 3: Flash the device using the pregenerated flash package.

1.   Make sure that the flash package is in the NFS file system, and fully
extracted (not a tarball!).

2.   Boot the device into NFS rootfs using the following commands:

$ cd Linux_for_Tegra
$ sudo ./tools/kernel_flash/l4t_create_flash_image_in_nfs.sh --flash-only \
-N <IPaddr>:<nfsroot> <board-name> <rootdev>

where
    <IPaddr>:<nfsroot> is the location of the NFS root to be used by the
    target to boot.

    <board-name> and <rootdev> variables are similar to those that are used for
    flash.sh. (See more details in official documentation's board name table).


3.   Once the target is rcm-booted into NFS, you can control the device through
a keyboard and monitor connected to the target. Another option is that you can
launch the l4t device mode terminal (if the prepared NFS root filesystem
supports it) using minicom:

$ sudo minicom -D /dev/ttyACMx

where
    ttyACMx is the device node exposed by your Jetson device. As there can be
    multiple Jetson devices connected to your computer, there can be multiple
    ttyACM device nodes: ttyACM0, ttyACM1, ttyACM2, corresponding to the number
    of devices connected to your computer. Replace ttyACMx with the device node
    that you want to control.

Once you have access to the device terminal, you can run the following command
on the target's NFS to flash target device:

$ sudo ${flash_package_location}/images_to_flash/${board_name}/l4t_flash_from_kernel.sh

where
    ${flash_package_location} is the location of the flash package.
    ${board-name} is the same board name used when creating.

The above flash command can also be automatically triggered by systemd after
device boots into NFS. See the sample nv-l4t-flash-from-nfs.service for more
details.






Workflow 4: Flash externally connected storage device.

Requirements:
To flash to an externally connected storage device, you need to create your own
flash.xml file for the external device. "For information about how to do this,
see the 'Partition Configuration' section in the developer guide. Additionally,
there is an example of a customized external storage table provided in the
same section.

1. Run commands below to flash external storage device alongside with internal storage:

$ cd Linux_for_Tegra
$ # Put device in recovery mode
$ sudo ./tools/kernel_flash/l4t_create_flash_image_in_nfs.sh \
                --external-device <external-device> \
                -c <external-partition-layout> \
                -S <APP-size> \
                -N <IPaddr>:<nfsroot> <board-name> <rootdev>

where
    <IPaddr>:<nfsroot> is the location of the NFS root to be used by the
    target to boot.

    <board-name> and <rootdev> variables are similar to those that are used for
    flash.sh. (See more details in the official documentation's board name
    table).

    <root-dev> can be set to "mmcblk0p1" or "internal" for booting from internal
    device or "external" for booting from external device.

    <external-partition-layout> is the partition layout for the external storage
    device in xml format.

    <external-device> is the name of the external storage device as it appears
    in the `/dev/` folder (i.e nvme0n1, sda).

    <APP-size> is the size of the partition that contains the operating system bytes
    KiB, MiB, GiB short hands are allowed, for example, 1GiB means 1024 * 1024 * 1024 bytes.

The result of the command is:
1) Generate images for an external device based on -c <layout>
2) Generate images for the internal device based on the given <board-name> and
<rootdev>

As an example, when flashing a Jetson AGX Xavier device with an external NVMe
SSD storage

Example:
    ./l4t_create_flash_image_in_nfs.sh --external-device nvme0n1
            -c external_storage_layout.xml
            -S 5120000000
            -N 192.168.0.21:/data/rootfs
            jetson-xavier
            mmcblk0p1

which will:

    1) Generate images for external device based on external_storage_layout.xml
    and set the size of the APP partition on the external storage partition to
    approximately 5GB (5120000000 bytes)

    2) Generate images for internal device for the Jetson Xavier device's internal
    mmcblk0p1. More specifically, it uses the following command internally:
        ./flash.sh --no-flash --sign jetson-xavier mmcblk0p1

    3) Do rcm-boot the target to the NFS at 192.168.0.21:/data/rootfs


2. Run commands to flash to external device only and rcm-boot to NFS:

    ./l4t_create_flash_image_in_nfs.sh --external-device nvme0n1
            --external-only
            -c external_storage_layout.xml
            -S 5120000000
            -N 192.168.0.21:/data/rootfs
            jetson-xavier
            mmcblk0p1

and then after you rcm-boot to NFS at 192.168.0.21:/data/rootfs on the target, run the following
command on the target terminal to flash external storage device only:

    $ sudo ${flash_package_location}/images_to_flash/${board_name}/l4t_flash_from_kernel.sh --external-only

where
    ${flash_package_location} is the location of the flash package.
    ${board-name} is the same board name used when creating.






Workflow 5: ROOTFS_AB support and boot from external device:


ROOTFS_AB is supported by setting the ROOTFS_AB environment variable to 1. For
examples:
    sudo ROOTFS_AB=1 ./l4t_create_flash_image_in_nfs.sh
            -N 192.168.0.21:/data/nfsroot \
            --external-device nvme0n1 \
            -S 5120000000 \
            -c external_storage_layout_rootfs_ab.xml \
            jetson-xavier \
            external

Workflow 6: Secureboot

With secureboot package installed, you can flash PKC fused and SBKPKC fused
Jetson. For examples:
    sudo ./l4t_create_flash_image_in_nfs.sh
        -N 192.168.0.21:/data/nfsroot \
        -u pkckey.pem \
        -v sbk.key \
        jetson-xavier \
        external