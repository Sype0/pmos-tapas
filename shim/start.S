/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Boot shim for tapas: lets the stock bootloader start a mainline kernel
 * with our own device tree.
 *
 * Xiaomi's ABL only takes boot images v4 (v1/v2 are ignored), and for those
 * it hands the kernel the DTB from vendor_boot (the downstream one, after
 * applying dtbo) and the vendor ramdisk instead of ours. So ABL is given this
 * shim as the "kernel": an arm64 Image header, then the code below, then a
 * descriptor and the payload appended by scripts/pack-shim.py:
 *
 *   0x0000   this code
 *   0x1000   descriptor (struct below)
 *   0x2000   our DTB
 *   0x200000 the kernel Image (initramfs built in)
 *
 * ABL enters at EL1 with the MMU and D-cache off and x0 = its DTB, which we
 * drop. The kernel must start at a 2 MB aligned address: if ABL put us on a
 * 2 MB boundary the kernel already is, otherwise it is copied to the next
 * 2 MB boundary after the payload. Then x0 = our DTB and off it goes.
 *
 * Progress shows as a bar at the top of the bootloader's framebuffer, so a
 * photo tells how far it got:
 *   blue   the shim runs (ABL took the image)
 *   yellow the kernel was copied
 *   green  jumping to the kernel
 *   red    bad descriptor (broken image)
 * After green, the kernel's own console takes over the screen.
 */

#define DESC_OFF	0x1000
#define DESC_MAGIC	0x4d494853	/* "SHIM" */

/* descriptor, all little endian u64 */
#define D_MAGIC		0
#define D_KERNEL_OFF	8
#define D_KERNEL_SIZE	16	/* bytes in the file */
#define D_KERNEL_MEM	24	/* image_size from the kernel's own header */
#define D_DTB_OFF	32
#define D_DTB_SIZE	40

#define FB_BASE		0x5c000000	/* continuous splash, 1080x2400 XRGB8888 */
#define FB_STRIDE	(1080 * 4)
#define BAR_ROWS	48

	.section .text.head, "ax"
	.globl	_head
_head:
	b	start			/* code0 */
	.long	0			/* code1 */
	.quad	0			/* text_offset */
	.quad	0			/* image_size, set by pack-shim.py */
	.quad	0xa			/* flags: little endian, 4K pages, place anywhere */
	.quad	0			/* res2 */
	.quad	0			/* res3 */
	.quad	0			/* res4 */
	.ascii	"ARM\x64"		/* magic */
	.long	0			/* res5 */

	.text
start:
	msr	daifset, #0xf
	adr	x20, _head		/* where ABL put us */

	mov	w0, #0x0000ff		/* blue */
	bl	bar

	add	x21, x20, #DESC_OFF
	ldr	x0, [x21, #D_MAGIC]
	movz	x1, #(DESC_MAGIC & 0xffff)
	movk	x1, #(DESC_MAGIC >> 16), lsl #16
	cmp	x0, x1
	b.ne	bad

	ldr	x22, [x21, #D_KERNEL_OFF]
	add	x22, x20, x22		/* kernel in the file */
	ldr	x23, [x21, #D_KERNEL_SIZE]
	ldr	x24, [x21, #D_KERNEL_MEM]
	ldr	x25, [x21, #D_DTB_OFF]
	add	x25, x20, x25		/* our DTB */
	ldr	x26, [x21, #D_DTB_SIZE]

	tst	x22, #0x1fffff
	b.eq	go

	/* Not 2 MB aligned: copy to the next 2 MB boundary after the file */
	add	x0, x22, x23
	mov	x1, #0x1fffff
	add	x0, x0, x1
	and	x0, x0, #~0x1fffff
	mov	x1, x22
	mov	x2, x23
	mov	x22, x0
1:	ldp	x3, x4, [x1], #16
	stp	x3, x4, [x0], #16
	subs	x2, x2, #16
	b.gt	1b
	/* Written with the D-cache off: drop any stale lines for the copy */
	mov	x0, x22
	mov	x1, x24
	mov	x6, #0
	bl	dcache_op
	mov	w0, #0xffff00		/* yellow */
	bl	bar
	b	1f

go:
	/* In place, as ABL loaded it */
	mov	x0, x22
	mov	x1, x24
	mov	x6, #1
	bl	dcache_op
1:	mov	x0, x25
	mov	x1, x26
	mov	x6, #1
	bl	dcache_op
	ic	iallu
	dsb	sy
	isb

	mov	w0, #0x00ff00		/* green */
	bl	bar

	mov	x0, x25			/* our DTB */
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	br	x22

bad:
	mov	w0, #0xff0000		/* red */
	bl	bar
2:	wfe
	b	2b

/* bar(w0 = XRGB colour): fill the top BAR_ROWS rows of the framebuffer */
bar:
	movz	x1, #(FB_BASE >> 16), lsl #16
	movz	x2, #((FB_STRIDE * BAR_ROWS) & 0xffff)
	movk	x2, #((FB_STRIDE * BAR_ROWS) >> 16), lsl #16
	orr	w0, w0, #0xff000000
3:	str	w0, [x1], #4
	subs	x2, x2, #4
	b.gt	3b
	dsb	sy
	ret

/*
 * dcache_op(x0 = start, x1 = size, x6): by VA to PoC, x6 = 0 invalidate,
 * 1 clean and invalidate (keeps anything ABL left dirty in what it loaded)
 */
dcache_op:
	mrs	x3, ctr_el0
	ubfx	x3, x3, #16, #4		/* DminLine: log2(words) */
	mov	x4, #4
	lsl	x4, x4, x3		/* line size in bytes */
	sub	x5, x4, #1
	add	x1, x0, x1
	bic	x0, x0, x5
4:	cbz	x6, 5f
	dc	civac, x0
	b	6f
5:	dc	ivac, x0
6:	add	x0, x0, x4
	cmp	x0, x1
	b.lo	4b
	dsb	sy
	ret
