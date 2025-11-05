/* SPDX-FileCopyrightText: 2024 Microwatt-InferSOC Project */
/* SPDX-License-Identifier: Apache-2.0 */

/* Linker script for Microwatt-Infer SoC firmware */

OUTPUT_ARCH(powerpc:common64)
ENTRY(_start)

MEMORY
{
    /* Code SRAM: 8KB at 0x00000000 */
    CODE_RAM (rx)  : ORIGIN = 0x00000000, LENGTH = 8K
    
    /* Data SRAM: 8KB at 0x00002000 (weight + activation) */
    DATA_RAM (rw)  : ORIGIN = 0x00002000, LENGTH = 8K
}

SECTIONS
{
    .text : {
        *(.text.start)
        *(.text*)
        *(.rodata*)
    } > CODE_RAM
    
    .data : {
        *(.data*)
        *(.sdata*)
    } > DATA_RAM
    
    .bss : {
        __bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        __bss_end = .;
    } > DATA_RAM
    
    /* Stack grows down from end of DATA_RAM */
    . = ORIGIN(DATA_RAM) + LENGTH(DATA_RAM);
    __stack_top = .;
    
    /DISCARD/ : {
        *(.comment)
        *(.eh_frame)
    }
}

