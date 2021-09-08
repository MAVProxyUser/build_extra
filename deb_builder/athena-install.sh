#!/bin/bash

rm /var/debs -rf
rm /var/lib/apt/lists/lock -rf
cp -r ./debs /var/

dpkg-scanpackages debs /dev/null | gzip > /var/debs/Packages.gz
mv /etc/apt/sources.list /etc/apt/sources.list.orig
if [ -e /etc/apt/sources.list.d/nvidia-l4t-apt-source.list ]; then
	mv /etc/apt/sources.list.d/nvidia-l4t-apt-source.list /etc/apt/sources.list.d/nvidia-l4t-apt-source.list.orig
fi
echo "deb [trusted=yes] file:/var/ debs/" > /etc/apt/sources.list

apt-get update

if [ "$1""x" = "ROSx" ]
then
	apt-get install -y athena-ros2
else
	apt-get install -y \
		athena-ota-server \
		athena-foxy-lib \
		athena-ros2 \
		athena-sensor \
		dobot-bootloader \
		dobot-kernel-headers \
		dobot-kernel-modules \
		athena-sys-config

	apt-get install -y athena-version
fi

mv /etc/apt/sources.list.orig /etc/apt/sources.list
if [ -e /etc/apt/sources.list.d/nvidia-l4t-apt-source.list.orig ]; then
	mv /etc/apt/sources.list.d/nvidia-l4t-apt-source.list.orig /etc/apt/sources.list.d/nvidia-l4t-apt-source.list
fi
rm /var/debs -rf
