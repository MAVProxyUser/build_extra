#!/bin/bash

rm /var/debs -rf
cp -r ./debs /var/

dpkg-scanpackages debs /dev/null | gzip > /var/debs/Packages.gz
mv /etc/apt/sources.list /etc/apt/sources.list.orig
mv /etc/apt/sources.list.d/nvidia-l4t-apt-source.list /etc/apt/sources.list.d/nvidia-l4t-apt-source.list.orig
echo "deb [trusted=yes] file:/var/ debs/" > /etc/apt/sources.list

apt-get update

apt-get install -y \
	athena-foxy-lib \
	athena-ros2 \
	athena-version

mv /etc/apt/sources.list.orig /etc/apt/sources.list
mv /etc/apt/sources.list.d/nvidia-l4t-apt-source.list.orig /etc/apt/sources.list.d/nvidia-l4t-apt-source.list
rm /var/debs -rf
