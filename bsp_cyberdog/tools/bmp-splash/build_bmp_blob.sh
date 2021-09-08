#!/bin/bash

#put bmp pictures in "bmp_files" folder,then build bmp blob for xiaomi, if you want to use new boot logo,plz mofidy
#partition xml file to assign "xiaomi_bmp.blob" to "BMP" partition.
OUT=$PWD ./genbmpblob_L4T.sh t210 ./config_file_xiaomi.txt ./BMP_generator_L4T.py /usr/bin/lz4c xiaomi_bmp.blob
