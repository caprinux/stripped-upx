/* nrv2b_d8.S -- ARM decompressor for NRV2B

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

#undef  GETBIT
#define GETBIT  bl get1_n2b

#define getnextb(reg) GETBIT; ADC2S(reg,reg) /* Set Condition Codes on result */
#define   jnextb0     GETBIT; bcc
#define   jnextb1     GETBIT; bcs

ucl_nrv2b_decompress_32: .globl ucl_nrv2b_decompress_32  // ARM mode
lr   .req x30
ip0  .req x16

src  .req x0
len  .req w1
dst  .req x2
dstw .req w2
tmp  .req w3
bits .req w4
off  .req w5
#ifndef NO_METHOD_CHECK
        cmp methb,#M_NRV2B_LE32; bne not_n2b
#endif
        .type ucl_nrv2b_decompress_32, %function
/* error = (*)(char const *src, uint32_t len_src, char *dst, uint32_t *plen_dst) */
        add x1,src,len,uxtw  // x1= eof_src;
        PUSH4(x1,x2,x3, lr)  // MATCH_90
        mov off,#-1  // off= -1 initial condition
        mov bits,#1<<31  // refill next time
        b top_n2b

#if defined(WINDOWS_BACK) || !defined(DAISY_CHAIN)  //{
eof_n2b:
        POP4(x1,x3,x4, lr)  // x1= eof_src; r3= orig_dst; r4= plen_dst
        SUB2(src,x1)  // 0 if actual src length equals expected length
        SUB2(dst,x3)  // actual dst length
        str dstw,[x4]
        mov x5,x0  // save result value

        mov x0,x3  // orig_dst
        add x1,x3,dst  // orig_dst + dst_len
#ifndef NO_SYNC_CACHE
        sync_cache  // x0= lo; x1= hi; uses x2-x4
#endif

        mov x0,x5  // result value
        ret

#endif  // WINDOWS_BACK  || ! DAISY_CHAIN }

get1_n2b:
        ADD2S(bits,bits); cbz bits,get32_n2b; ret
get32_n2b:  // In: Carry set [from adding 0x80000000 (1<<31) to itself]
        LDR3(bits,[src],#4)
        ADC2S(bits,bits)  // left shift 1 bit with CarryIn and CarryOut
        ret

ss11_n2b:  // return len= [2..)
        mov len,#1  // the msb
        mov ip0,lr  // outer ret.addr
1:
        getnextb(len)
        jnextb0 1b
        br ip0  // outer ret

lit_n2b:
        LDRB3(tmp,[src],#1)
        STRB3(tmp,[dst],#1)
top_n2b:
        jnextb1 lit_n2b

        bl ss11_n2b  // len= [2..)
        subs tmp,len,#3  // set Carry
        mov len,#0  // Carry unaffected
        blo offprev_n2b  // ss11 returned 2
        LDRB3(off,[src],#1)  // low 8 bits
        orr  off,off,tmp,lsl #8
        mvn off,off; cbz off,eof_n2b  // off= ~off
offprev_n2b:  // In: 0==len
        getnextb(len); getnextb(len); bne 1f  // two bits; 1,2,3 ==> 2,3,4
        bl ss11_n2b  // len= [2..)
        ADD2(len,#2)  // [2..) ==> [4..);
1:
/* 'cmn': add the inputs, set condition codes, discard the sum */
        cmn off,#0xd<<8  // within M2_MAX_OFFSET
        cinc len,len,cc  // too far away, so minimum match length is 3
copy_n2b:  // copy 1+len bytes
        ldrb  tmp,[dst,off,sxtw]; SUB2S(len,#1)
        STRB3(tmp,[dst],#1); bhs copy_n2b
        b top_n2b  // exit with -1==len


#ifndef NO_METHOD_CHECK
not_n2b:
#endif
        # fall into daisy chain
    .unreq lr
    .unreq ip0

    .unreq src
    .unreq len
    .unreq dst
    .unreq dstw
    .unreq tmp
    .unreq bits
    .unreq off
        .size ucl_nrv2b_decompress_32, .-ucl_nrv2b_decompress_32
/*
vi:ts=8:et:nowrap
 */

