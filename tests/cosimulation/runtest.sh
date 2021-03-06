#!/bin/sh

# 
# Copyright 2011-2013 Jeff Bush
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# 

ASM=../../tools/assembler/assemble
ISS=../../tools/simulator/iss
VERILATOR_MODEL=../../rtl/obj_dir/Vverilator_tb
#ISS_DEBUG_ARGS=-v # Display register transfers from instruction set simulator

mkdir -p WORK

for test in "$@"
do
	if [ "${test##*.}" != 'hex' ]
	then
		echo "Assembling $test"
		PROGRAM=WORK/test.hex
		$ASM -o $PROGRAM $test
		if [ $? -ne 0 ]
		then
			exit 1
		fi
	else
		echo "Executing $test"
		PROGRAM=$test
	fi

	$VERILATOR_MODEL +regtrace=1 +bin=$PROGRAM +simcycles=500000 +memdumpfile=WORK/vmem.bin +memdumpbase=0 +memdumplen=A0000 +autoflushl2=1 | $ISS $ISS_DEBUG_ARGS -c -d WORK/mmem.bin,0,A0000 $PROGRAM

	if [ $? -eq 0 ]
	then
		diff WORK/vmem.bin WORK/mmem.bin
		if [ $? -eq 0 ]
		then
			echo "PASS"
		else
			echo "FAIL: final memory contents do not match"
			exit 1
		fi
	fi
done

