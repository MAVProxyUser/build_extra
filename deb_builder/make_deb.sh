#!/bin/bash
#
function recalc_md5sum()
{
	local REPACK_DIR=$1
	local METADATA_DIR="${REPACK_DIR}/DEBIAN"
	echo "Recalulating md5sum"
	pushd "${REPACK_DIR}" > /dev/null
	# All files in DEBIAN/ and all conffiles are omitted from the md5sums file per dh_md5sums
	find . -type f ! -path "./${METADATA_DIR##*/}/*" ! -path "./etc/*" | LC_ALL=C sort | xargs md5sum | \
		sed -e 's@\./@ @' > "${METADATA_DIR}/md5sums"
	popd > /dev/null
}

function recalc_installed_size()
{
	local REPACK_DIR=$1
	local METADATA_DIR="${REPACK_DIR}/DEBIAN"
	echo "Recalulating the installed size"
	installed_size=0
	list=($(find "${REPACK_DIR}" \( -type f -o -type l \) \
		! -path "*/${METADATA_DIR##*/}/control" ! -path "*/${METADATA_DIR##*/}/md5sums"))
	for file in "${list[@]}"; do
		size=$(stat -c %s "${file}")
		((installed_size+=(${size}+1023)/1024))
	done

	((installed_size+=$(find "${REPACK_DIR}" ! \( -type f -o -type l \) | wc -l)))
	sed -ri "s/(^Installed-Size:) ([0-9]*)$/\1 ${installed_size}/" "${METADATA_DIR}/control"
}
#=====================================
filepath=$(cd "$(dirname "$0")"; pwd)

j=0
for i in `ls -d *deb`
do
	deb_array[j]=$i
	j=`expr $j + 1`
done

index=0
i=0

if [ -z "$1" ]
then
	for var in ${deb_array[@]}
	do
		i=$(( $i+1 ))
		echo "$i - $var"
	done
	i=$(( $i+1 ))
	echo "$i - ALL"
	echo "Which deb do you want package:"
	read index
elif [ "$1""x" = "ALLx" ]
then
	index=$(($j+1))
	echo "Make debs for all packages."
else
	for var in ${deb_array[@]}
	do
		i=$(( $i+1 ))
		if [ "$var" = "$1" ]
		then
			index=$i
			break
		fi
	done
	if [ $index == 0 ]
	then
		echo "Package $1 not found."
	fi
fi

if [ $index -eq $(($j+1)) ]
then
	for var in ${deb_array[@]}
	do
		chmod g-s $filepath/$var/src/* -R
		recalc_md5sum $filepath/$var/src
		recalc_installed_size $filepath/$var/src
		dpkg -b $filepath/$var/src/ $filepath/debs
	done
elif [ $index -le $j ] && [ $index -gt 0 ]
then
	deb=$filepath/${deb_array[($index-1)]}
	echo "package $deb"
	chmod g-s $deb/src/* -R
	recalc_md5sum $deb/src
	recalc_installed_size $deb/src
	dpkg -b $deb/src/ $filepath/debs
else
	echo "failed select deb package"
fi
