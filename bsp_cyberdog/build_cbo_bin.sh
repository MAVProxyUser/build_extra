#!/bin/bash

#if you want to use cbo.dtb to change boot order,plz mofidy partition xml file to assign "cbo.dtb" to "CPUBL-CFG" partition.
./kernel/dtc -I dts -O dtb -o ./bootloader/cbo.dtb ./bootloader/cbo.dts
