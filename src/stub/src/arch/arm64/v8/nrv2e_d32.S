/* nrv2e_d32.S -- ARM decompressor for NRV2E

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
#include "macros.S"

#define SAFE 0  /* 1 for src+dst bounds checking: cost 76 bytes */

lr   .req x30

src  .req x0
len  .req w1  /* overlaps 'cnt' */
dst  .req x2
dstw .req w2
#define tmpw w3  /*bug: .req w3 */
#define tmpx x3  /*bug: .req x3 */
bits .req w4
off  .req w5
/*           r6  UNUSED in ARM code unless DEBUG mode */
srclim .req x7
#if 1==SAFE  /*{*/
dstlim .req x12
#endif  /*}*/

#define cnt  w1  /* overlaps 'len' while reading an offset */

#if 1==SAFE  /*{*/
#define CHECK_SRC  cmp srclim,src; bls bad_src_n2e /* Out: 1==Carry for get32_n2e */
#define CHECK_DST  cmp dst,dstlim; bhs bad_dst_n2e
#else  /*}{*/
#define CHECK_SRC  /*empty*/
#define CHECK_DST  /*empty*/
#endif  /*}*/

#if 0  /*{ DEBUG only: check newly-decompressed against original dst */
#define CHECK_BYTE \
   ldrb  w6,[dst]; \
   cmp   w6,tmpw; beq 0f; bkpt; 0:
#else  /*}{*/
#define CHECK_BYTE  /*empty*/
#endif  /*}*/

#undef GETBIT
#define GETBIT bl get1_n2e

#undef getnextb
#define getnextb(reg) GETBIT; ADC2(reg,reg) /* Out: condition code not changed */
#define   jnextb0     GETBIT; bcc
#define   jnextb1     GETBIT; bcs

ucl_nrv2e_decompress_32: .globl ucl_nrv2e_decompress_32  // ARM mode
        .type ucl_nrv2e_decompress_32, %function
#ifndef NO_METHOD_CHECK
        cmp methb,#M_NRV2E_LE32; bne not_n2e
#endif
/* error = (*)(char const *src, uint32_t len_src, char *dst, uint32_t *plen_dst)
   Actual decompressed length is stored through plen_dst.
   For SAFE mode: at call, *plen_dst must be allowed length of output buffer.
*/
        PUSH1(lr)  // MATCH_91
        PUSH2(x2,x3)  // MATCH_92
#define sp_DST0 0  /* stack offset of original dst */
        add srclim,src,len,uxtw  // srclim= eof_src;
#if 1==SAFE  /*{*/
        ldr tmpw,[r3]  // len_dst
        add dstlim,tmpw,dst
#endif  /*}*/
        mov off,#-1  // off= -1 initial condition
        mov bits,#1<<31  // refill next time
        b top_n2e

#if 1==SAFE  /*{*/
bad_dst_n2e:  # return value will be 2
        add src,srclim,#1
bad_src_n2e:  # return value will be 1
        ADD2(src,#1)
#endif  /*}*/

#if defined(WINDOWS_BACK) || !defined(DAISY_CHAIN)  //{
eof_n2e:
        POP2(x3,x4)  // MATCH_92  r3= orig_dst; r4= plen_dst
        SUB2(src,srclim)  // 0 if actual src length equals expected length
        SUB2(dst,x3)  // actual dst length
        str dstw,[x4]
        mov x5,x0  // save result value

        mov x0,x3  // orig_dst
        add x1,x3,dst  // orig_dst + dst_len
cache_n2e:  // unused label
#ifndef NO_SYNC_CACHE
        sync_cache  // x0= lo; x1= hi; uses x2-x4
#endif

        mov x0,x5  // result value
        POP1(lr)  // MATCH_91
        ret
#endif  // WINDOS_BACK || ! DAISY_CHAIN }

get1_n2e:
        ADD2S(bits,bits); cbz bits,get32_n2e; ret
get32_n2e:  // In: Carry set [from adding 0x80000000 (1<<31) to itself]
        CHECK_SRC; ldr bits,[src],#4
        ADC2S(bits,bits)  // left shift 1 bit with CarryIn and CarryOut
        ret

lit_n2e:
        CHECK_SRC; LDRB3(tmpw,[src],#1)
        CHECK_BYTE
        CHECK_DST; STRB3(tmpw,[dst],#1)
top_n2e:
        jnextb1 lit_n2e
        mov cnt,#1; b getoff_n2e

off_n2e:
        SUB2(cnt,#1)
        getnextb(cnt)
getoff_n2e:
        getnextb(cnt)
        jnextb0 off_n2e

        subs tmpw,cnt,#3  // set Carry
        mov len,#0  // Carry unaffected
        blo offprev_n2e  // cnt was 2; tests Carry only
        CHECK_SRC; LDRB3(off,[src],#1)  // low 7+1 bits
        orr  off,off,tmpw,lsl #8
        mvn off,off; cbz off,eof_n2e  // off= ~off
        tst off,#1; asr off,off,#1; bne lenlast_n2e
        b lenmore_n2e

offprev_n2e:
        jnextb1 lenlast_n2e
lenmore_n2e:
        mov len,#1
        jnextb1 lenlast_n2e
len_n2e:
        getnextb(len)
        jnextb0 len_n2e
        ADD2(len,#6-2)
        b gotlen_n2e

lenlast_n2e:
        getnextb(len)  // 0,1,2,3
        ADD2(len,#2)
gotlen_n2e:  // 'cmn': add the inputs, set condition codes, discard the sum
        cmn off,#5<<8  // within M2_MAX_OFFSET
        cinc len,len,cc  // too far away, so minimum match length is 3
near_n2e:
#if 1==SAFE  /*{*/
        ldr tmpw,[sp,#sp_DST0]
        SUB2( tmpw,dst)
        SUB2S(tmpw,off); bhi bad_dst_n2e  // reaching back too far

        add tmpw,dst,cnt
        cmp tmpw,dstlim; bhi bad_dst_n2e  // too much output
#endif  /*}*/
        add tmpx,dst,len,uxtw
        ldrb tmpw,[tmpx,#-1]  // force cacheline allocate
copy_n2e:
        ldrb tmpw,[dst,off,sxtw]
        CHECK_BYTE
        STRB3(tmpw,[dst],#1)
        SUB2S(len,#1); bne copy_n2e
        b top_n2e

#ifndef NO_METHOD_CHECK
not_n2e:
#endif
        # fall into daisy_chain

        .size ucl_nrv2e_decompress_32, .-ucl_nrv2e_decompress_32
    .unreq lr
    .unreq src
    .unreq len
    .unreq dst
    .unreq dstw
#undef tmpw  //    .unreq tmpw
#undef tmpx  //    .unreq tmpx
    .unreq bits
    .unreq off
    .unreq srclim
#if 1==SAFE  //{
    .unreq dstlim
#endif  //}

/*
vi:ts=8:et:nowrap
 */

