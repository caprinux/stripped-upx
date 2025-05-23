/* powerpc64le-linux.elf-entry.S -- Linux program entry point & decompressor (Elf binary)
*
*  This file is part of the UPX executable compressor.
*
*  Copyright (C) 1996-2025 Markus Franz Xaver Johannes Oberhumer
*  Copyright (C) 1996-2025 Laszlo Molnar
*  Copyright (C) 2000-2025 John F. Reiser
*  All Rights Reserved.
*
*  UPX and the UCL library are free software; you can redistribute them
*  and/or modify them under the terms of the GNU General Public License as
*  published by the Free Software Foundation; either version 2 of
*  the License, or (at your option) any later version.
*
*  This program is distributed in the hope that it will be useful,
*  but WITHOUT ANY WARRANTY; without even the implied warranty of
*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*  GNU General Public License for more details.
*
*  You should have received a copy of the GNU General Public License
*  along with this program; see the file COPYING.
*  If not, write to the Free Software Foundation, Inc.,
*  59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*
*  Markus F.X.J. Oberhumer              Laszlo Molnar
*  <markus@oberhumer.com>               <ezerotven+github@gmail.com>
*
*  John F. Reiser
*  <jreiser@users.sourceforge.net>
*/

#ifndef BIG_ENDIAN
#error  BIG_ENDIAN must be #define as 0 or 1
#endif

NBPW= 8  // Number of Bytes Per Word
#include "arch/powerpc/64/macros.S"
#include "arch/powerpc/64/ppc_regs.h"

sz_b_info= 12
  sz_unc= 0
  sz_cpr= 4
  b_method= 8

AT_NULL= 0  // <elf.h>
AT_PAGESZ= 6
a_type= 0
a_val= NBPW
sz_auxv= 2*NBPW

O_RDONLY=  0

PROT_READ=  1
PROT_WRITE= 2
PROT_EXEC=  4

MAP_PRIVATE= 2
MAP_FIXED=     0x10
MAP_ANONYMOUS= 0x20
MFD_EXEC= 0x10

CACHELINE=32

/* /usr/include/asm-ppc/unistd.h */
__NR_exit  = 1
__NR_memfd_create= 360
__NR_mmap  = 90
__NR_mprotect = 125
__NR_munmap = 91
__NR_close = 6
__NR_open =  5
__NR_write = 4

  section ELFMAINX
sz_pack2= .-4
_start: .globl _start
////    teq r0,r0  // DEBUG
        call main  // link_register= &f_exp  (&decompress)
f_exp:

/* Returns 0 on success; non-zero on failure. */
decompress:  // (uchar const *src, size_t lsrc, uchar *dst, size_t &ldst, uint method)

SZ_DLINE=128  # size of data cache line in Apple G5

/* PowerPC has no 'cmplis': compare logical [unsigned] immediate shifted [by 16] */
#define  hibit r0  /* holds 0x80000000 during decompress */

#define src  a0
#define lsrc a1
#define dst  a2
#define ldst a3  /* Out: actually a reference: &len_dst */
#define meth a4

#define off  a4
#define len  a5
#define bits a6
#define disp a7

#include "arch/powerpc/64le/nrv2b_d.S"

eof_nrv:
#define dst0 a4
#define tmp a1
        ld dst0,0(ldst)  // original dst
        mtlr t3  // return address
        subf a0,lsrc,src
        subf tmp,dst0,dst  // -1+ dst length
        addi a0,a0,1  // return 0: good; else: bad  [+1: correct for lbzu]
        addi tmp,tmp,1  // dst length
        std  tmp,0(ldst)
#undef tmp

// CACHELINE=32 is the observed minimum line size of any cache.
// Some caches may have larger lines, but it is cumbersome to lookup
// {AT_DCACHEBSIZE, AT_ICACHEBSIZE, AT_UCACHEBSIZE: /usr/include/elf.h},
// then save the correct size in a variable {where to put it?}, or to modify
// the two instructions here.  If a cache has larger lines, then we expect
// that the second dcbst (or icbi) on a the same line will be fast.
// If not, then too bad.

        ori dst0,dst0,-1+ CACHELINE  // highest addr on cache line
cfl_nrv:
        dcbst  0,dst0  // initiate store (modified) cacheline to memory
        cmpld cr0,dst0,dst  // did we cover the highest-addressed byte?
        icbi   0,dst0  // discard instructions from cacheline
        addi     dst0,dst0,CACHELINE  // highest addr on next line
        blt  cr0,cfl_nrv  // not done yet
#undef dst0
        sync   // wait for all memory operations to finish
        isync  // discard prefetched instructions (if any)
cfl_ret:
        ret

  section ELFMAINY
        // IDENTSTR goes here

#if BIG_ENDIAN  //{
  section ELFMAINZe
        .balign 8
        .globl entry_descr
entry_descr:  // Elf64_Ehdr.e_entry points here (big endian only)
        .quad _start,0,0
#endif  //}

  section ELFMAINZ

r_exp=   31
r_fp=    30
r_ADRU=  29
r_LENU=  28
r_fd=    27
r_auxv=  26
r_elf=   25
r_ADRX=  24
r_LENX=  23
r_FLD=   22
r_szuf=  21
r_PMASK= 20
r_obinf= 19

        /* Decompress the rest of this loader, and jump to it. */
unfold:  // IN: r_auxv, r_PMASK
        mflr r_FLD  // LrFLD

        lwz r0,  sz_pack2 - f_exp(r_exp)
        la  r_elf,sz_pack2 - f_exp(r_exp)
        sub r_elf,r_elf,r0  // r_elf=&Elf32_Ehdr of stub
        lwz r_LENU, sz_unc + LBINFO - LrFLD(r_FLD)  // sz_unc of fold

        call 0f; .asciz "upx"; 0:
        mflr a0
        li a1,MFD_EXEC
SYS_memfd_create= __NR_memfd_create
        li r0,SYS_memfd_create; sc; bns+ 0f; teq r0,r0; 0:
        mr r_fd,a0

//Reserve enough space to decompress the folded code of the stub
        mr r_fp,sp
        li r0,-CACHELINE
// alloca
        sub sp,sp,r_LENU
        and sp,sp,r0

        lwz r_obinf,      LOBINFO - LrFLD(r_FLD)  // O_BINFO
// Decompress folded code
        mtctr r_exp
        lbz meth,b_method + LBINFO - LrFLD(r_FLD)
        std  r_LENU,SZ_FRAME+31*NBPW(r_fp)  // lzma uses for EOF
        la ldst,    SZ_FRAME+31*NBPW(r_fp)  // &slot on stack
        mr dst,sp  // dst for unfolding
        lwz lsrc,sz_cpr  + LBINFO - LrFLD(r_FLD)
        la src,sz_b_info + LBINFO - LrFLD(r_FLD)  // folded code
        bctrl  // f_exp (decompress)
        std r_PMASK,0(sp)  // forward the actual page_mask

        mr a0,r_fd
        mr a1,sp
        mr a2,r_LENU
SYS_write= __NR_write
        li r0,SYS_write; sc; bns+ 0f; teq r0,r0; 0:
        mr sp,r_fp

        li a5,0
        mr a4,r_fd
        li a3,MAP_PRIVATE
        li a2,PROT_EXEC|PROT_READ  // PROT_WRITE: DEBUG only
        mr a1,r_LENU
        li a0,0
SYS_mmap= __NR_mmap
        li r0,SYS_mmap; sc; bns+ 0f; teq r0,r0; 0:
        mr r_ADRU,a0

        mr a0,r_fd
// r_fd dead
SYS_close= __NR_close
        li r0,SYS_close; sc; bns+ 0f; teq r0,r0; 0:

// Use the unfolded code
        addi r0,r_ADRU,2*NBPW  // skip page_mask, other word
        add r_ADRX,r_elf,r_obinf  // compressed data
        mtctr r0
        li r0,(SZ_FRAME+32*NBPW)/NBPW  // words before &argc
        lwz r_LENX, sz_pack2 - f_exp(r_exp)
        bctr

zfind:
        ld r0,0(a0); addi a0,a0,NBPW
        cmpdi cr7,r0,0; bne+ cr7,zfind
        ret

main:
////    teq r0,r0  // debugging
        stdu r1,-(SZ_FRAME + 32*NBPW)(sp)  // FR_00  allocate space (keeping 0 mod 16), save r1
//      stmd r2,SZ_FRAME+(-1+  2)*NBPW(sp) // save registers r2 thru r31
        std   2,SZ_FRAME+(-1+  2)*NBPW(sp)
        std   3,SZ_FRAME+(-1+  3)*NBPW(sp)
        std   4,SZ_FRAME+(-1+  4)*NBPW(sp)
        std   5,SZ_FRAME+(-1+  5)*NBPW(sp)
        std   6,SZ_FRAME+(-1+  6)*NBPW(sp)
        std   7,SZ_FRAME+(-1+  7)*NBPW(sp)
        std   8,SZ_FRAME+(-1+  8)*NBPW(sp)
        std   9,SZ_FRAME+(-1+  9)*NBPW(sp)
        std  10,SZ_FRAME+(-1+ 10)*NBPW(sp)
        std  11,SZ_FRAME+(-1+ 11)*NBPW(sp)
        std  12,SZ_FRAME+(-1+ 12)*NBPW(sp)
        std  13,SZ_FRAME+(-1+ 13)*NBPW(sp)
        std  14,SZ_FRAME+(-1+ 14)*NBPW(sp)
        std  15,SZ_FRAME+(-1+ 15)*NBPW(sp)
        std  16,SZ_FRAME+(-1+ 16)*NBPW(sp)
        std  17,SZ_FRAME+(-1+ 17)*NBPW(sp)
        std  18,SZ_FRAME+(-1+ 18)*NBPW(sp)
        std  19,SZ_FRAME+(-1+ 19)*NBPW(sp)
        std  20,SZ_FRAME+(-1+ 20)*NBPW(sp)
        std  21,SZ_FRAME+(-1+ 21)*NBPW(sp)
        std  22,SZ_FRAME+(-1+ 22)*NBPW(sp)
        std  23,SZ_FRAME+(-1+ 23)*NBPW(sp)
        std  24,SZ_FRAME+(-1+ 24)*NBPW(sp)
        std  25,SZ_FRAME+(-1+ 25)*NBPW(sp)
        std  26,SZ_FRAME+(-1+ 26)*NBPW(sp)
        std  27,SZ_FRAME+(-1+ 27)*NBPW(sp)
        std  28,SZ_FRAME+(-1+ 28)*NBPW(sp)
        std  29,SZ_FRAME+(-1+ 29)*NBPW(sp)
        std  30,SZ_FRAME+(-1+ 30)*NBPW(sp)
        std  31,SZ_FRAME+(-1+ 31)*NBPW(sp)
        mflr r_exp  // &f_exp (decompress)

        la a0,SZ_FRAME+32*NBPW +NBPW(sp)  // &argv  (argc might be zero!)
        call zfind  // a0= envp
        call zfind  // a0= &Elf64_auxv
        mr r_auxv,a0  // save for folded code

// set r_PMASK by finding actual page size in Elf64_auxv_t
1:
        ld r0,a_type(a0); ld a1,a_val(a0); addi a0,a0,sz_auxv
        cmpdi cr7,r0,AT_PAGESZ; beq- cr7,2f
        cmpdi cr0,r0,AT_NULL;   bne+ cr0,1b
        lis a1,1  // not found; use default (1<<16)
2:
        neg r_PMASK,a1  // save for folded code

        call unfold
LrFLD:
LOBINFO:
        .long O_BINFO  // .int4
LBINFO:

        /* { b_info={sz_unc, sz_cpr, {4 char}}, folded_loader...} */

/* vim:set ts=8 sw=8 et: */
