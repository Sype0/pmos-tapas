/* SPDX-License-Identifier: GPL-2.0-only */
/* Position independent (adr only), so the link address does not matter. */
ENTRY(_head)
SECTIONS
{
	. = 0;
	.text : { *(.text.head) *(.text) *(.text.vectors) }
	/DISCARD/ : { *(.data*) *(.bss*) *(.comment) *(.note*) *(.eh_frame*) }
}
