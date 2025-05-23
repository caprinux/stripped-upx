/*
;  amd64-expand.S -- decompressors for amd64
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

NBPW= 8
#include "arch/amd64/regs.h"
#include "arch/amd64/macros.S"

/* AMD64 branch prediction is much worse if there are more than 3 branches
   per 16-byte block.  The jnextb would suffer unless inlined.  getnextb is OK
   using closed subroutine to save space, and should be OK on cycles because
   CALL+RET should be predicted.  getnextb could partially expand, using closed
   subroutine only for refill.
*/
/* jump on next bit {0,1} with prediction {y==>likely, n==>unlikely} */
/* Prediction omitted for now. */
/* On refill: prefetch next byte, for latency reduction on literals and offsets. */
#define jnextb0np jnextb0yp
#define jnextb0yp GETBITp; jnc
#define jnextb1np jnextb1yp
#define jnextb1yp GETBITp; jc
#define GETBITp \
        addl bits,bits; jnz 0f; \
        movl (%rsi),bits; sub $-4,%rsi; \
        adcl bits,bits; movzbl (%rsi),%edx; \
0:
/* Same, but without prefetch (not useful for length of match.) */
#define jnextb0n jnextb0y
#define jnextb0y GETBIT; jnc
#define jnextb1n jnextb1y
#define jnextb1y GETBIT; jc
#define GETBIT \
        addl bits,bits; jnz 0f; \
        movl (%rsi),bits; sub $-4,%rsi; \
        adcl bits,bits; \
0:

/* rotate next bit into bottom bit of reg */
#define getnextbp(reg) GETBITp; adcl reg,reg
#define getnextb(reg)  getnextbp(reg)

// /*************************************************************************
//   C-callable decompressor  f_expand(&b_info, dst, &dstlen)
// **************************************************************************/

  section EXP_HEAD
f_expand: .globl f_expand   // start of code for actual de-compressor
        push %rbp; mov %rsp,%rbp; push %rbx  // MATCH_50  C saved registers

// Calling sequence registers
#define fx_src %rdi  /* includes b_info for .b_method, .b_ftid, .b_cto8 */
#define fx_dst %rsi
#define fx_dstlen %rdx
#define meth  %r8d
#define methb %r8b


sz_unc= 0
sz_cpr= 4
b_method= 8
b_ftid=   9
b_cto8=  10
b_extra= 11
sz_binfo= 12

    push fx_dstlen; push fx_dst; push fx_src  // MATCH_54
    call decompress
    pop %rbx  // fx_src
    pop %rdi  // fx_dst  arg1
    pop %rsi  // MATCH_54  fx_dstlen
    push %rax  // MATCH_55  save result from decompress

    movzbl b_ftid(%rbx),%ecx  // arg4
    test %ecx,%ecx; jz no_unf  // 0==.ftid
    movzbl b_cto8(%rbx),%edx  // arg3
    movl (%rsi),%esi  // arg2= dstlen
    call unfilter  // (*f_unf)(xo->buf, out_len, h.b_cto8, h.b_ftid);
no_unf:
    pop %rax  // MATCH_55  restore result from decompress
    pop %rbx; pop %rbp  // MATCH_50
    ret

unfilter:
#include "arch/amd64/bxx.S"  // !NO_METHOD_CHECK; ordinary C call+ret


/* NRV2 working registers */
#define off  %eax  /* XXX: 2GB */
#define len  %ecx  /* XXX: 2GB */
#define lenq %rcx
#define bits %ebx
#define src %rsi
#define dst %rdi
#define displ %ebp
#define dispq %rbp

decompress:  // (fx_src= &b_info, fx_dst= dst, fx_dstlen= &dstlen)
    push fx_dstlen  // MATCH_51
    movzbl b_method(fx_src),meth  // daisy chain by decompression method
    push fx_src; push fx_dst
    pop  dst;    pop  src
    mov sz_cpr(src),%eax; add $sz_binfo,src  // done with b_info; ready for movsb, lodsb
    add src,%rax; push %rax  // MATCH_52  src_EOF
    push dst  // MATCH_53  dst_orig

        xor bits,bits  // empty; force refill
        xor len,len  // create loop invariant
        orq $(~0),dispq  // -1: initial displacement
        jmp go_meth

refill:
        movl (%rsi),bits; sub $-4,%rsi  // next 32 bits; set Carry
        adcl bits,bits  // LSB= 1 (CarryIn); CarryOut= next bit
        movzbl (%rsi),%edx  // speculate: literal, or bottom 8 bits of offset
        rep; ret
getbit:
        endbr64  // from "call *%rdx"
        addl bits,bits; jz refill  // Carry= next bit
        rep; ret

copy:  // In: len, %rdi, dispq;  Out: 0==len, %rdi, dispq;  trashes %rax, %rdx
        lea (%rdi,dispq),%rax; cmpl $5,len  // <=3 is forced
        movzbl (%rax),%edx; jbe copy1  // <=5 for better branch predict
        cmpl $-4,displ;   ja  copy1  // 4-byte chunks would overlap
        subl $4,len  // adjust for termination cases
copy4:
        movl (%rax),%edx; add $4,      %rax; subl $4,len
        movl %edx,(%rdi); lea  4(%rdi),%rdi; jnc copy4
        addl $4,len; movzbl (%rax),%edx; jz copy0
copy1:
        inc %rax; movb %dl,(%rdi); dec len
            movzbl (%rax),%edx
                lea 1(%rdi),%rdi;  jnz copy1
copy0:
        rep; ret

go_meth:
        cld

#define M_NRV2B_LE32    2
#define M_NRV2D_LE32    5
#define M_NRV2E_LE32    8
#define M_CL1B_LE32     11
#define M_LZMA          14

// Daisy chain of decoding methods that were used
#define NO_METHOD_CHECK 1  /* subsumed here by daisy chain */

  section NRV2E
    cmp $M_NRV2E_LE32,meth; jne not_nrv2e
#include "arch/amd64/nrv2e_d.S"
not_nrv2e:

  section NRV2D
    cmp $M_NRV2D_LE32,meth; jne not_nrv2d
#include "arch/amd64/nrv2d_d.S"
not_nrv2d:

  section NRV2B
    cmp $M_NRV2B_LE32,meth; jne not_nrv2b
#include "arch/amd64/nrv2b_d.S"
not_nrv2b:

#undef off
#undef len
#undef lenq
#undef bits
#undef displ
#undef dispq

section LZMA_DAISY
    cmp $M_LZMA,meth; jne not_lzma

section LZMA_ELF00  // prefix for parameter juggling
        push dst; push src  // MATCH_60
#define arg2d esi
        mov sz_cpr - sz_binfo(src),%arg2d
#undef src
#undef dst
        mov fx_dstlen,%arg4
        pop %arg1; pop %arg3  // MATCH_60

#include "arch/amd64/lzma_d.S"
not_lzma:

  section EXP_TAIL
// Fall through: daisy chain had no matching method
        mov meth,%ecx  // b_method as __NR__
        or $~0,%eax  // "errno"
        int3; hlt  // no method

eof_lzma:
eof_n2b:
eof_n2d:
eof_n2e:
        pop %rax  // MATCH_53 dst_orig
        sub %rax,%rdi  // dst -= original dst
        pop %rax  // MATCH_52 src_EOF
        pop %rcx  // MATCH_51 &dstlen
        movl %edi,(%rcx)  // actual length used at dst  XXX: 4GB
        sub %rsi,%rax  // src -= eof;  // return 0: good; else: bad
        ret

        .balign 4
upx_mmap_and_fd: .globl upx_mmap_and_fd
    // UMF_LINUX goes here
