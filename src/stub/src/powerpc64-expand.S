/*
;  powerpc64-expand.S -- decompressors for powerpc64le
;
;  This file is part of the UPX executable compressor.
;
;  Copyright (C) 1996-2021 Markus Franz Xaver Johannes Oberhumer
;  Copyright (C) 1996-2021 Laszlo Molnar
;  Copyright (C) 2000-2021 John F. Reiser
;  All Rights Reserved.
;
;  UPX and the UCL library are free software; you can redistribute them
;  and/or modify them under the terms of the GNU General Public License as
;  published by the Free Software Foundation; either version 2 of
;  the License, or (at your option) any later version.
;
;  This program is distributed in the hope that it will be useful,
;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;  GNU General Public License for more details.
;
;  You should have received a copy of the GNU General Public License
;  along with this program; see the file COPYING.
;  If not, write to the Free Software Foundation, Inc.,
;  59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
;
;  Markus F.X.J. Oberhumer              Laszlo Molnar
;  <markus@oberhumer.com>               <ezerotven+github@gmail.com>
;
;  John F. Reiser
;  <jreiser@users.sourceforge.net>
;
*/

#if !defined(BIG_ENDIAN)  //{
#error must "#define BIG_ENDIAN" as 0 or 1
#endif  //}

NBPW= 8
SZ_DLINE= 128  # size of data cache line in Apple G5

#include "arch/powerpc/64/ppc_regs.h"
#include "arch/powerpc/64/macros.S"

  section EXP_HEAD

sz_unc= 0
sz_cpr= 4
b_method= 8
b_ftid=   9
b_cto8=  10
b_extra= 11
sz_binfo= 12

f_expand: .globl f_expand // f_expand(b_info *, dst, &dstlen)
    .type f_expand,function
// Supervisor for de-compression, un-filter, and sync_cache
// Input to supervisor:
#define fx_src    a0
#define fx_dst    a1
#define fx_dstlen a2
    mflr r0
    PUSH4 fx_src,fx_dst,fx_dstlen,r0  // MATCH_80  params to unfilter and sync_cache

// Input to de-compressor:
#define xsrc    a0
#define xsrclen a1
#define xdst    a2
#define xdstlen a3
#define methb   a4
    lbz methb,b_method(fx_src)
    movr xdstlen,fx_dstlen  // arg4
    movr xdst,fx_dst  // arg3
    lwz xsrclen,sz_cpr(xsrc)  // arg2  FIXME? possibly unaligned fetch
    addi xsrc,fx_src,sz_binfo // arg1
    call decompress
    movr a3,a0  // save retval

    POP3 a2,a0,a1   // MATCH_80  fx_src,fx_dst,fx_dstlen; keep f_expand.retaddr
    ld a1,0(a1)  // actual length used by decompressor
    PUSH3 a0,a1,a3  // MATCH_81  params for sync_cache
    lbz a3,b_ftid(a2)
    lbz a2,b_cto8(a2)
    cmpi cr0,a3,0; beq no_unf
    call unfilter
no_unf:

    POP2 a0,a1   // MATCH_81  dst, len
    add a1,a1,a0  // lo, hi

CACHELINE=32
        ori a0,a0,-1+ CACHELINE  // highest addr on cache line
cfl_nrv:
        dcbst  0,a0  // initiate store (modified) cacheline to memory
        cmpl cr0,a0,a1  // did we cover the highest-addressed byte?
        icbi   0,a0  // discard instructions from cacheline
        addi     a0,a0,CACHELINE  // highest addr on next line
        blt  cr0,cfl_nrv  // not done yet
        sync   // wait for all memory operations to finish
        isync  // discard prefetched instructions (if any)
cfl_ret:
    POP2 a0,r0   // MATCH_80, MATCH_81  retval, retaddr from f_expand
    mtlr r0
    ret
//    .unreq fx_src
//    .unreq fx_dst
//    .unreq fx_dstlen
//    .unreq xsrc
//    .unreq xsrclen
//    .unreq xdst
//    .unreq xdstlen
//    .unreq methb

decompress:  // (src *, cpr_len, dst *, &dstlen);
//  sections NRV2B, etc, inserted here by addLoader() from ::buildLinuxLoader()

  section EXP_TAIL
// Fall through: daisy chain had no matching method
        mr a0,methb
        teq a0,a0

#define M_NRV2B_LE32    2
#define M_NRV2B_8    3
#define M_NRV2D_LE32    5
#define M_NRV2D_8    6
#define M_NRV2E_LE32    8
#define M_NRV2E_8    9
#define M_CL1B_LE32     11
#define M_LZMA          14

#define  hibit r0  /* holds 0x80000000 during decompress */

#define src  a0
#define lsrc a1
#define dst  a2
#define ldst a3  /* Out: actually a reference: &len_dst */
#define meth a4

    .globl eof_nrv
eof_nrv:
#define tmp a1
#define dst0 a4
        ld dst0,0(ldst)  // original dst
        mtlr t3  // return address
        subf a0,lsrc,src
        subf tmp,dst0,dst  // -1+ dst length
        addi a0,a0,1  // return 0: good; else: bad  [+1: correct for lbzu]
        addi tmp,tmp,1  // dst length
        std  tmp,0(ldst)
        blr
#undef tmp
#undef dst0

unfilter:
#include "arch/powerpc/64/bxx.S"  // unfilter code; args in registers, fall-through return

#define NO_METHOD_CHECK 1  /* subsumed here by daisy chain */

#define off  a4
#define len  a5
#define bits a6
#define disp a7

  section NRV2E
    cmpwi meth,M_NRV2E_LE32; bne not_nrv2e
#if BIG_ENDIAN
#include "arch/powerpc/64/nrv2e_d.S"
#else
#include "arch/powerpc/64le/nrv2e_d.S"
#endif
not_nrv2e:

  section NRV2D
    cmpwi meth,M_NRV2D_LE32; bne not_nrv2d
#if BIG_ENDIAN
#include "arch/powerpc/64/nrv2d_d.S"
#else
#include "arch/powerpc/64le/nrv2d_d.S"
#endif
not_nrv2d:

  section NRV2B
    cmpwi meth,M_NRV2B_LE32; bne not_nrv2b
#if BIG_ENDIAN
#include "arch/powerpc/64/nrv2b_d.S"
#else
#include "arch/powerpc/64le/nrv2b_d.S"
#endif
not_nrv2b:

#undef off
#undef len
#undef bits
#undef disp

#undef src
#undef lsrc
#undef dst
#undef ldst

  section LZMA_DAISY
    cmpwi meth,M_LZMA; bne not_lzma
#undef meth
#if BIG_ENDIAN
#include "arch/powerpc/64/lzma_d.S"
#else
#include "arch/powerpc/64le/lzma_d.S"
#endif

section LZMA_DEC30  // appended to LZMA_DEC30 from src/arch/powerpc/32/lzma_d.S
//eof_lzma:
        ret  // normal return from LzmaDecode
not_lzma:
        // daisy-chain fall through (or EXP_TAIL)
