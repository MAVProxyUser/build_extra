************************************************************************
                              Linux for Jetson
                             Flash using initrd
                                   README
************************************************************************
The NVIDIA Jetson Linux Package provides tools to flash the Jetson devices from
the host using recovery kernel initrd running on the target. This document
describes in detail the procedure for "flashing using initrd".

Requirements:
- This tool uses NetworkManager to configure the network to do flashing.
Therefore, your host environment needs to use NetworkManager and not other
conflicting network managers.
- This tool makes use of USB mass storage during flashing; therefore,
automount of new external storage device needs to be disabled temporarily
during flashing. On most distributions of Debian-based Linux, you can do this
using the following command:
      $ systemctl stop udisks2.service
- This tool requires the host to have the following dependencies:
      $ sudo apt install libxml2-utils simg2img network-manager abootimg sshpass # For Debian-based Linux
- Some mode of operations requires Ubuntu 18.04 or above

How to use:
-     This tool supports T194 and T186 devices. You can use the -h option to find out what options this tool supports.
-     Below are listed some sample workflows for initrd flashing.


Workflow 1: How to flash single devices in one step
Steps:
- Make sure you have only ONE device in recovery mode plugged in the host
- Run this command from the Linux_for_Tegra folder:
      $ sudo ./tools/kernel_flash/l4t_initrd_flash <board-name> <rootdev>
Where <board-name> and <rootdev> are similar to the corresponding variables used
in the flash.sh command. (See more details in the official documentation's
board name table).



Workflow 2: How to generate images first and flash the target later.
Steps:
- Make sure you have only ONE device in recovery mode plugged into the host
- Run this command from the Linux_for_Tegra folder to generate flash images:

With device connected (online mode):
$ sudo ./tools/kernel_flash/l4t_initrd_flash --no-flash <board-name> <rootdev>

Without device connected (offline mode):
$ sudo BOARDID=<BOARDID> FAB=<FAB> BOARDSKU=<BOARDSKU> BOARDREV=<BOARDREV> \
./tools/kernel_flash/l4t_initrd_flash --no-flash <board-name> <rootdev>

- Put the device in recovery mode again
- Run this command from the Linux_for_Tegra folder:
$ sudo ./tools/kernel_flash/l4t_initrd_flash --flash-only <board-name> <rootdev>
Where <board-name> and <rootdev> are similar to the corresponding variables used
in the flash.sh command. (See more details in the official documentation's
board name table).




Workflow 3: How to flash to an external storage device attached to a Jetson
Requirements

To flash to an externally connected storage device, you need to create your own
flash.xml file for the external device. For information about how to do this,
see the 'Partition Configuration' section in the developer guide. Additionally,
there is an example of a customized external storage table provided in the
same section. There are also two examples xml files in the tools/kernel_flash
folder:
- flash_l4t_nvme.xml contains both the rootfs, kernel and kernel-dtb on the external
storage device so that the Jetson target does not have to use emmc or sdcard for
booting
- flash_l4t_nvme_disc_enc.xml is an example partition configuration used for
disc encryption feature on external storage.

Workflow 1: Flash external device:
- Run this command from the Linux_for_Tegra folder:
$ sudo ./tools/kernel_flash/l4t_initrd_flash --external-device <external-device> \
      -c <external-partition-layout> \
      [ --external-only ] \
      -S <APP-size> <board-name> <rootdev>
Where
- <board-name> and <rootdev> variables are similar to those that are used for
flash.sh. (See more details in the official documentation's board name
table).
- <root-dev> can be set to "mmcblk0p1" or "internal" for booting from internal
device or "external", "sda1" or "nvme0n1p1" for booting from external device.
If your external device's external partition layout has "APP" partition, specifying here "nvme0n1p1"
will generate the rootfs boot commandline: root=/dev/nvme0n1p1. If <rootdev> is internal or
external, the tool will generate rootfs commandline: root=PARTUUID=...

- <external-partition-layout> is the partition layout for the external storage
device in XML format.
- <external-device> is the name of the external storage device you want to flash
as it appears in the '/dev/' folder (i.e nvme0n1, sda).

- <APP-size> is the size of the partition that contains the operating system in bytes.
KiB, MiB, GiB shorthand are allowed, for example, 1GiB means 1024 * 1024 * 1024 bytes.
This size cannot be bigger than num_sectors * sector_size specified in the
partition layout
- Use --external-only to flash only the external storage device


Example usage:
Flash an nvme SSD and use APP partition on it as root filesystem
sudo ./tools/kernel_flash/l4t_initrd_flash.sh --external-device nvme0n1p1 -c ~/Downloads/flash_l4t_nvme.xml -S 5120000000  --showlogs  jetson-xavier nvme0n1p1

Flash USB connected storage use APP partition on it as root filesystem
sudo ./tools/kernel_flash/l4t_initrd_flash.sh --external-device sda1 -c ~/Downloads/flash_l4t_nvme.xml -S 5120000000  --showlogs  jetson-xavier sda1

Flash an nvme SSD and use partition with UUID specified in l4t-rootfs-uuid.txt_ext as root filesystem
sudo ./tools/kernel_flash/l4t_initrd_flash.sh --external-device nvme0n1p1 -c ~/Downloads/flash_l4t_nvme.xml -S 5120000000  --showlogs  jetson-xavier external



Initrd flash depends on --external-device options and the last parameter <rootdev>
to generate the correct images. The following combinations are supported:
+-------------------+-----------------+-------------------------------------------------------+
| --external-device |       <rootdev> | Results                                               |
+-------------------+-----------------+-------------------------------------------------------+
| nvme*n*p* / sda*  |        internal | External device contains full root filesystem with    |
|                   |                 | kernel commandline: rootfs=PARTUUID=<external-uuid>   |
|                   |                 |                                                       |
|                   |                 | Internal device contains full root filesystem with    |
|                   |                 | kernel commandline: rootfs=PARTUUID=<internal-uuid>   |
+-------------------+-----------------+-------------------------------------------------------+
| nvme*n*p* / sda*  | nvme0n*p* / sd* | External device  contains full root filesystem with   |
|                   |                 | with kernel commandline rootfs=/dev/nvme0n1p1         |
|                   |                 |                                                       |
|                   |                 | Internal device contains minimal file system with     |
|                   |                 | kernel command line rootfs=/dev/nvme0n1p1             |
+-------------------+-----------------+-------------------------------------------------------+
| nvme*n*p* / sda*  |       mmcblk0p1 | External device  contains full root filesystem with   |
|                   |                 | with kernel commandline rootfs=/dev/nvme0n1p1         |
|                   |                 |                                                       |
|                   |                 | Internal device contains minimal file system with     |
|                   |                 | kernel command line rootfs=/dev/mmcblk0p1             |
+-------------------+-----------------+-------------------------------------------------------+
| nvme*n*p* / sda*  |        external | External device contains full root filesystem with    |
|                   |                 | kernel commandline: rootfs=PARTUUID=<external-uuid>   |
|                   |                 |                                                       |
|                   |                 | Internal device contains minimal root filesystem with |
|                   |                 | kernel commandline: rootfs=PARTUUID=<external-uuid>   |
+-------------------+-----------------+-------------------------------------------------------+
| nvme*n* / sda     | *               | External device contains full root filesystem with    |
|                   |                 | kernel commandline: rootfs=PARTUUID=<external-uuid>   |
|                   |                 |                                                       |
|                   |                 | Internal device image depends <rootdev>. Please look  |
|                   |                 | at the above entries.                                 |
+-------------------+-----------------+-------------------------------------------------------+




Workflow 4: ROOTFS_AB support and boot from external device:
ROOTFS_AB is supported by setting the ROOTFS_AB environment variable to 1. For
example:
sudo ROOTFS_AB=1 ./l4t_initrd_flash.sh
      --external-device nvme0n1 \
      -S 5120000000 \
      -c external_storage_layout_rootfs_ab.xml \
      jetson-xavier \
      external





Workflow 5: Secureboot
With Secureboot package installed, you can flash PKC fused and SBKPKC fused
Jetson. For example:
$ sudo ./l4t_initrd_flash.sh
      -u pkckey.pem \
      -v sbk.key \
      jetson-xavier \
      external





Workflow 6: Initrd Massflash
Initrd Massflash works with workflow 3,4,5. Initrd Massflash works in a similar way to
the Massflash package. See README_Massflash.txt for more background. Similar to
Massflash, Initrd massflash also requires you to do the massflash in two steps.

First, generate massflash package using options --no-flash and --massflash <x>
Where <x> is the highest possible number of device to be flashed concurrently
In the example below, we create an flashing environment that is capable of flashing
5 devices concurrently.

$ sudo ./tools/kernel_flash/l4t_initrd_flash.sh --no-flash --massflash 5 jetson-xavier-nx-devkit-emmc mmcblk0p1
Now, your Linux_for_Tegra folder contains a package that is capable of massflash.
You can copy the Linux_for_Tegra folder to the environment where you want to do
massflash.

Second,
- Connect the Jetson devices to the flashing hosts.
(Make sure all devices are in exactly the same hardware revision similar to the requirement in
README_Massflash.txt )
- Put all of connected Jetsons into RCM mode.
- Run:
$ sudo ./tools/kernel_flash/l4t_initrd_flash.sh --flash-only --massflash 5
(Optionally add --showlogs to show all of the log)

If you generate the massflash package with the signing key and encryption key (applied to Workflow
5: Secureboot), the tool generates a tarbal with the name mfi_<target-board>.tar.gz that contains
all the minimal binaries needed to flash in an unsecure environment. Download this
tarball to the unsafe environment, untar the tarball to create a flashing environment
and execute similar step to flash:

$ sudo tar xpfv mfi_<target-board>.tar.gz
$ cd mfi_<target-board>
$ # Make sure all connected Jetson are in RCM mode and have exactly the same hardware revision (i.e same BOARDID, BOARDSKU, FAB)
$ sudo ./tools/kernel_flash/l4t_initrd_flash.sh --flash-only --massflash 5




Tips:
- For massflash, the initrd tool copy the bootloader folder to create a flash environment. This potentially makes the massflash process really slow if the bootloader folder is really large. The tool solves this by excluding files whose name match regex system*.img and system*.raw.  Therefore, if you are to use your own binary for a partition, it is good to name it so that it matches the regex system*.img so that the tool knows to exclude it during flash environment creation.
- The tool also provide options --keep to keep the flash environment, and --reuse to reuse the flash environment. So one could do this, to make massflash run faster:
Massflash the first time.
sudo ./tools/kernel_flash/l4t_initrd_flash.sh --flash-only --massflash 5 --keep
Massflash the second time.
sudo ./tools/kernel_flash/l4t_initrd_flash.sh --flash-only --massflash 5 --reuse
- Use ionice to make the flash process  the highest I/O priority in the system.
sudo ionice -c 1 -n 0 ./tools/kernel_flash/l4t_initrd_flash.sh --flash-only --massflash 5







Workflow 7: Flash inidividual partition

Initrd flash have an option to flash individual partitions based on the index file.
When running initrd flash, index files are generated under tools/kernel_flash/images
based on the partition configuration layout xml (flash.idx for internal storage,
flash.idx.ext for external storage). Using "-k" option, initrd flash can flash one
partition based on the partition label specified in the index file.

Examples:
$ sudo ./tools/kernel_flash/l4t_initrd_flash.sh -k eks jetson-xavier mmcblk0p1
