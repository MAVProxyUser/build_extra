#!/bin/bash
echo "Before collecting version info:"
cat ./ota_versions_all.json
#1-Collect deb package versions
#./debs/athena-factory-tool_1.0.15_arm64.deb, like this
deb_array=($(ls ./debs/*.deb))
#echo "${deb_array[@]}"
for tmp_deb in ${deb_array[@]}
do
	#echo "${tmp_deb}"
	deb_name=${tmp_deb//"./debs/"/""}
	pack_name_n_verison=${deb_name%_*}
	pack_info_array=(${pack_name_n_verison//"_"/" "})
	echo "${pack_info_array[@]}"
	sed -i "s/\"${pack_info_array[0]}\".*/\"${pack_info_array[0]}\" : \"${pack_info_array[1]}\",/" ./ota_versions_all.json
done

#2-Collect version of motion control
motion_ctrl_version=$(ls ./p2151_update*.img)
motion_ctrl_version=${motion_ctrl_version##*/}
motion_ctrl_version=${motion_ctrl_version##*-}
motion_ctrl_version=${motion_ctrl_version%.*}
echo $motion_ctrl_version
sed -i "s/\"motion-control\".*/\"motion-control\" : \"${motion_ctrl_version}\",/" ./ota_versions_all.json

#3-Collect versions of head/bot/rear
stm32_version_info=$(cat ./athena_sensor_deb/src/usr/bin/stm32_version_info)
if [[ ! (${stm32_version_info} =~ "rear") ]]; then
	echo "No rear version, plz check stm32_version_info !"
	exit 1
fi

if [[ ! (${stm32_version_info} =~ "bot") ]]; then
	echo "No bot version, plz check stm32_version_info !"
	exit 1
fi
if [[ ! (${stm32_version_info} =~ "head") ]]; then
	echo "No head version, plz check stm32_version_info !"
	exit 1
fi

stm32_info_array=(${stm32_version_info//";"/" "})
for tmp_info in ${stm32_info_array[@]}
do
	if [[ ${tmp_info} =~ "head" ]]; then
		head_ver=${tmp_info#*:}
		sed -i "s/\"head\".*/\"head\" : \"${head_ver}\",/" ./ota_versions_all.json
	fi
	
	if [[ ${tmp_info} =~ "bot" ]]; then
		bot_ver=${tmp_info#*:}
		sed -i "s/\"bot\".*/\"bot\" : \"${bot_ver}\",/" ./ota_versions_all.json
	fi
	
	if [[ ${tmp_info} =~ "rear" ]]; then
		rear_ver=${tmp_info#*:}
		sed -i "s/\"rear\".*/\"rear\" : \"${rear_ver}\",/" ./ota_versions_all.json
	fi
done

#4-postprocess
#Remove blank line
sed -i '/^$/d; /^[[:space:]]*$/d' ./ota_versions_all.json

#Remove the last ',' of the file 
line_cnt=0
while read LINE && [[ -n $LINE  ]]
do
	line_cnt=$[ $line_cnt + 1 ];
done < ./ota_versions_all.json
last_ver_line_num=$[ $line_cnt - 1 ]
#echo "last_ver_line_num=${last_ver_line_num}"
sed -i "${last_ver_line_num}s/,//" ./ota_versions_all.json

echo "After collecting version info:"
cat ./ota_versions_all.json
