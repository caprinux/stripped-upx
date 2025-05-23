/* lzma_d.S -- ARM decompressor for LZMA

   This file is part of the UPX executable compressor.

   Copyright (C) 1996-2025 Markus Franz Xaver Johannes Oberhumer
   Copyright (C) 1996-2025 Laszlo Molnar
   Copyright (C) 2000-2025 John F. Reiser
   All Rights Reserved.

   UPX and the UCL library are free software; you can redistribute them
   and/or modify them under the terms of the GNU General Public License as
   published by the Free Software Foundation; either version 2 of
   the License, or (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; see the file COPYING.
   If not, write to the Free Software Foundation, Inc.,
   59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

   Markus F.X.J. Oberhumer              Laszlo Molnar
   <markus@oberhumer.com>               <ezerotven+github@gmail.com>

   John F. Reiser
   <jreiser@users.sourceforge.net>
*/

#define section .section

  section LZMA_ELF00
//decompress:  // (uchar const *src, size_t lsrc, uchar *dst, u32 &ldst, uint method)
/* Arguments according to calling convention */
src  .req r0
lsrc .req r1
dst  .req r2
ldst .req r3  /* Out: actually a reference: &len_dst */

  // bkpt  // debugging

#if defined(LINUX_ARM_CACHEFLUSH)||defined(DARWIN_ARM_CACHEFLUSH)  /*{*/
        PUSH {dst,ldst, fp,lr}  // dst,ldst for cache flush
#else  /*}{*/
        PUSH {          fp,lr}
#endif  /*}*/

a0 .req r0
#define a1 r1  // bug: a1 .req r1
#define a2 r2  // bug: a2 .req r2
#define a3 r3  // bug: a3 .req r3
#define a4    [sp,#0*4] /* outp */
#define a5    [sp,#1*4] /* outSize */
#define a6    [sp,#2*4] /* &outSizeProcessed */
#define inSzP      3*4  /*   inSizeprocessed */
#define State      4*4  /* CLzmaDecoderState */

//LzmaDecode(  // from lzmaSDK/C/7zip/Compress/LZMA_C/LzmaDecode.h
//      a0= &CLzmaDecoderState,
//      a1= inp,  a2= inSize,  a3= &inSizeProcessed,
//      a4= outp, a5= outSize, a6= &outSizeProcessed
//)
#define LZMA_BASE_SIZE 1846
#define LZMA_LIT_SIZE   768

        ldrb fp,[src,#0]  // first byte, replaces LzmaDecodeProperties()
        mov ip,#2*LZMA_LIT_SIZE
        mov fp,fp,LSR #3  // lit_context_bits + lit_pos_bits
        mov ip,ip,LSL fp  // 2*LZMA_LIT_SIZE << (lit_context_bits + lit_pos_bits)
        mov fp,sp
#define W 4  /* even #bits to round up so that 8 bits span all the 1's */
        add ip,ip,#((~(~0<<W) + State + 2*LZMA_BASE_SIZE)>>W)<<W
        sub sp,sp,ip

        ldr ip,[ldst]
        str ldst,a6  // &outSizeProcessed
        str ip,  a5  // outSize
        str dst, a4   // outp

        add r3,sp,#inSzP
        mov ip,#0
1:  // clear inSizeProcessed and CLzmaDecoderState
        str ip,[r3],#4
        cmp r3,fp
        bne 1b

        add a3,sp,#inSzP // &inSizeProcessed
        sub a2,lsrc,#2  // inSize
        mov a1, src  // inp

        ldrb ip,[a1],#1  // first byte, replaces LzmaDecodeProperties()
        and  ip,ip,#7  // posBits
        strb ip,[sp,#2 + State]
        ldrb ip,[a1],#1  // second byte, replaces LzmaDecodeProperties()
        mov  a0,ip,LSR #4  // lit_pos_bits
        strb a0,[sp,#1 + State]
        and  ip,ip,#0xf  // lib_context_bits
        strb ip,[sp,#0 + State]

        add a0,sp,#State
        bl 1f  // call C-language LzmaDecompress
        mov sp,fp

#if defined(LINUX_ARM_CACHEFLUSH)  /*{*/
        mov r3,r0  // save result value
        POP {r0,r1}  // dst, ldst
        ldr r1,[r1]  // ldst by reference
        add r1,r1,r0  // just beyond what was written
        mov r2,#0
        do_sys2 __ARM_NR_cacheflush  // decompressed region
        mov r0,r3  // result value
#endif  /*}*/
#if defined(DARWIN_ARM_CACHEFLUSH)  /*{*/
        mov r4,r0  // save result value
        POP {r0,r1}  // dst, ldst
        ldr r1,[r1]  // ldst by reference
        PUSH {r0,r1}; do_dcache_flush
        POP  {r0,r1}; do_icache_invalidate
        mov r0,r4  // result value
#endif  /*}*/

        POP {fp,pc}  // RETURN!

1: // either LZMA_DEC10 or LZMA_DEC20 inserted next by buildLinuxLoader

  section LZMA_DEC20
#include "lzma_d_cf.S"

  section LZMA_DEC10
#if 0  /*{*/
#include "lzma_d_cs.S"
#else  /*}{*/
#define PARAMETER_STYLE 3
#include "lzma_d-arm.S"
#endif  /*}*/

  section LZMA_DEC30

// vi:ts=8:et

