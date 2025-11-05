# SPDX-FileCopyrightText: 2024 Microwatt-InferSOC Project
# SPDX-License-Identifier: Apache-2.0

# Firmware Makefile for Microwatt-Infer SoC

# Cross-compiler for PowerPC64 little-endian
CROSS_COMPILE ?= powerpc64le-linux-gnu-

CC = $(CROSS_COMPILE)gcc
LD = $(CROSS_COMPILE)ld
OBJCOPY = $(CROSS_COMPILE)objcopy
OBJDUMP = $(CROSS_COMPILE)objdump

# Compiler flags for Microwatt (no FPU, bare metal)
CFLAGS = -Os -g -Wall -std=c99 -msoft-float -mno-string -mno-multiple -mno-vsx -mno-altivec
CFLAGS += -mlittle-endian -fno-stack-protector -mstrict-align -ffreestanding -fdata-sections -ffunction-sections
CFLAGS += -I.

# Linker flags
LDFLAGS = -T linker.ld -nostdlib -Wl,--gc-sections

# Target binaries
TARGET = demo
OBJS = demo.o ml_accel.o

all: $(TARGET).bin $(TARGET).hex

$(TARGET).elf: $(OBJS) linker.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(OBJS)

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

$(TARGET).hex: $(TARGET).elf
	$(OBJCOPY) -O ihex $< $@

$(TARGET).lst: $(TARGET).elf
	$(OBJDUMP) -d $< > $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f *.o *.elf *.bin *.hex *.lst

.PHONY: all clean

