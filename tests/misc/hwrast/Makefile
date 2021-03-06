# 
# Copyright 2011-2012 Jeff Bush
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

WORKDIR=WORK
LOCAL_TOOL_DIR=../../../tools
COMPILER_DIR=/usr/local/llvm-vectorproc/bin
CC=$(COMPILER_DIR)/clang
AS=$(COMPILER_DIR)/llvm-mc
LD=$(COMPILER_DIR)/lld
OBJDUMP=$(COMPILER_DIR)/llvm-objdump
PROFILER=$(LOCAL_TOOL_DIR)/misc/profile.py
ISS=$(LOCAL_TOOL_DIR)/simulator/iss
VERILATOR=../../../rtl/obj_dir/Vverilator_tb
MKBMP=$(LOCAL_TOOL_DIR)/mkbmp/mkbmp
CFLAGS=-Wall -W -O3 -fno-rtti -std=c++11 -target vectorproc
ASFLAGS=-filetype=obj -triple vectorproc-elf
LDFLAGS=-flavor gnu -static -target vectorproc

SRCS=main.cpp

OBJS := $(SRCS:%.cpp=$(WORKDIR)/%.o) $(WORKDIR)/start.o
DEPS := $(SRCS:%.cpp=$(WORKDIR)/%.d)

$(WORKDIR)/program.hex: $(WORKDIR)/program.elf
	$(LOCAL_TOOL_DIR)/flatten_elf/flatten_elf $@ $<
	
$(WORKDIR)/program.elf: $(DEPS) $(OBJS) 
	$(LD) $(LDFLAGS) -o $@ $(OBJS)
	$(OBJDUMP) --disassemble WORK/program.elf > program.lst 2> /dev/null	# Make disassembly file

$(WORKDIR)/%.o : %.cpp 
	@echo "Compiling $<..."
	@$(CC) $(CFLAGS) -o $@ -c $<

$(WORKDIR)/%.o : %.s
	@echo "Assembling $<..."
	@$(AS) $(ASFLAGS) -o $@ $<

$(WORKDIR)/%.d: %.cpp
	@echo "Building dependencies for $<..."
	@mkdir -p $(dir $@)
	@$(CC) $(CFLAGS) -o $(WORKDIR)/$*.d -MM $<

clean:
	rm -rf $(WORKDIR)

# Run in verilator
run: $(WORKDIR)/program.hex
	$(VERILATOR) +bin=$(WORKDIR)/program.hex

-include $(DEPS)

