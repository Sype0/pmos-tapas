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
 * drop. ABL loads the image low in RAM (base 0x40000000), where the kernel
 * with its BSS would run into the hypervisor and the other carveouts from
 * 0x45700000 up, so the kernel is copied to KERNEL_DEST, at the start of the
 * free 1 GB bank (KERNEL_ALT if ABL happened to put us there). Then x0 = our
 * DTB and off it goes.
 *
 * Progress shows on the bootloader's framebuffer in bands of BAND rows from
 * the top, so a photo tells how far it got:
 *   0  blue     the shim runs
 *   1  bits     where ABL loaded us, bits 63..32
 *   2  bits     the same, bits 31..0
 *   3  yellow   one block per 2 MB of kernel copied
 *   4  green    jumping to the kernel
 *   5  red      bad descriptor (broken image)
 *      magenta  synchronous exception, cyan IRQ, white FIQ, orange SError
 *   6  bits     ESR_EL1          \
 *   7  bits     FAR_EL1 63..32    | after an exception
 *   8  bits     FAR_EL1 31..0     |
 *   9  bits     ELR_EL1 - load   /
 *  10  bits     SCTLR_EL1 at entry
 *  11  bits     CurrentEL at entry
 * Bits read most significant first, 1 bright, 0 dark, every other nibble in
 * a second pair of colours (white/grey, then orange/navy).
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

#define KERNEL_DEST	0x80000000	/* 1 GB bank, nothing reserved below 0x89b01000 */
#define KERNEL_ALT	0xc0000000

#define FB_BASE		0x5c000000	/* continuous splash, 1080x2400 XRGB8888 */
#define FB_WIDTH	1080
#define FB_STRIDE	(FB_WIDTH * 4)
#define BAND		48
#define CHUNK		0x200000	/* copy progress: one block per chunk */
#define BLOCK_W		40
#define BLOCKS		(FB_WIDTH / BLOCK_W)

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
	mrs	x27, sctlr_el1
	mrs	x28, CurrentEL
	adr	x0, vectors
	msr	vbar_el1, x0
	isb
	msr	daifclr, #4		/* let SErrors show */

	mov	w0, #0x0000ff		/* blue */
	mov	x1, #0
	bl	bar
	lsr	x0, x20, #32
	mov	x1, #1
	bl	bits
	mov	w0, w20
	mov	x1, #2
	bl	bits
	mov	w0, w27
	mov	x1, #10
	bl	bits
	mov	w0, w28
	mov	x1, #11
	bl	bits

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

	/* KERNEL_DEST, or KERNEL_ALT if that overlaps the file */
	mov	x27, #KERNEL_DEST
	add	x0, x22, x23		/* end of the file */
	add	x1, x27, x24		/* end of the kernel at KERNEL_DEST */
	cmp	x20, x1
	ccmp	x27, x0, #2, lo		/* x20 < x1: overlap if also x27 < x0, else C set */
	b.hs	1f
	mov	x27, #KERNEL_ALT
1:
	/* Copy in CHUNKs, a yellow block after each */
	mov	x9, x22
	mov	x10, x27
	mov	x11, x23
	mov	x19, #0
2:	mov	x12, #CHUNK
	cmp	x11, x12
	csel	x12, x11, x12, lo
	sub	x11, x11, x12
3:	ldp	x3, x4, [x9], #16
	stp	x3, x4, [x10], #16
	subs	x12, x12, #16
	b.gt	3b
	mov	x2, #BLOCKS
	udiv	x3, x19, x2
	msub	x0, x3, x2, x19		/* block % BLOCKS */
	mov	x2, #BLOCK_W
	mul	x0, x0, x2
	mov	x1, #(3 * BAND)
	mov	x2, #(BLOCK_W - 4)
	mov	x3, #(BAND - 4)
	mov	w4, #0xffff00		/* yellow */
	bl	rect
	add	x19, x19, #1
	cbnz	x11, 2b

	/* Written with the D-cache off: drop any stale lines for the copy */
	mov	x0, x27
	mov	x1, x24
	mov	x6, #0
	bl	dcache_op
	mov	x0, x25
	mov	x1, x26
	mov	x6, #1
	bl	dcache_op
	ic	iallu
	dsb	sy
	isb

	mov	w0, #0x00ff00		/* green */
	mov	x1, #4
	bl	bar

	mov	x0, x25			/* our DTB */
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	br	x27

bad:
	mov	w0, #0xff0000		/* red */
	mov	x1, #5
	bl	bar
	b	hang

/* exception: w19 = colour of the vector it came through */
exc:
	mov	w0, w19
	mov	x1, #5
	bl	bar
	mrs	x0, esr_el1
	mov	x1, #6
	bl	bits
	mrs	x21, far_el1
	lsr	x0, x21, #32
	mov	x1, #7
	bl	bits
	mov	w0, w21
	mov	x1, #8
	bl	bits
	mrs	x0, elr_el1
	sub	x0, x0, x20
	mov	x1, #9
	bl	bits
hang:
	wfe
	b	hang

/* rect(x0 = x, x1 = y, x2 = width, x3 = height, w4 = XRGB), uses x0-x8 */
rect:
	orr	w4, w4, #0xff000000
	mov	x5, #FB_STRIDE
	mov	x6, #FB_BASE
	madd	x6, x1, x5, x6
	add	x6, x6, x0, lsl #2
4:	mov	x7, x2
	mov	x8, x6
5:	str	w4, [x8], #4
	subs	x7, x7, #1
	b.gt	5b
	add	x6, x6, x5
	subs	x3, x3, #1
	b.gt	4b
	dsb	sy
	ret

/* bar(w0 = XRGB, x1 = band): fill the band, uses x0-x8, x16 */
bar:
	mov	x16, x30
	mov	w4, w0
	mov	x2, #BAND
	mul	x1, x1, x2
	mov	x0, #0
	mov	x2, #FB_WIDTH
	mov	x3, #(BAND - 4)
	bl	rect
	ret	x16

/* bits(w0 = value, x1 = band): its 32 bits, MSB left, uses x0-x15 */
bits:
	mov	x15, x30
	mov	w9, w0
	mov	x2, #BAND
	mul	x10, x1, x2
	mov	x11, #0
6:	mov	w12, #31
	sub	w12, w12, w11
	lsr	w12, w9, w12
	ubfx	x13, x11, #2, #1	/* odd nibble */
	tbz	w12, #0, 7f
	mov	w4, #0xffffff		/* 1: white */
	mov	w14, #0xff8000		/*    orange */
	b	8f
7:	mov	w4, #0x40404040		/* 0: grey (rect sets the top byte) */
	mov	w14, #0x000060		/*    navy */
8:	cmp	x13, #0
	csel	w4, w4, w14, eq
	mov	x0, #33
	mul	x0, x11, x0
	mov	x1, x10
	mov	x2, #28
	mov	x3, #(BAND - 8)
	bl	rect
	add	x11, x11, #1
	cmp	x11, #32
	b.lo	6b
	ret	x15

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
9:	cbz	x6, 10f
	dc	civac, x0
	b	11f
10:	dc	ivac, x0
11:	add	x0, x0, x4
	cmp	x0, x1
	b.lo	9b
	dsb	sy
	ret

/*
 * Exception vectors, only to show that one was taken. 16 entries of 0x80
 * bytes; the table ends at 0x1000, where the descriptor starts.
 */
	.section .text.vectors, "ax"
	.balign	0x800
vectors:
	.irp	colour, 0xff00ff, 0x00ffff, 0xffffff, 0xff8000, 0xff00ff, 0x00ffff, 0xffffff, 0xff8000
	.balign	0x80
	mov	w19, #\colour
	b	exc
	.endr
	.rept	8			/* from lower ELs: not expected */
	.balign	0x80
	mov	w19, #0x800080		/* purple */
	b	exc
	.endr
	.balign	0x80
