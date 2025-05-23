/*  mipsel-linux.elf-fold.S -- linkage to C code to process Elf binary
*
*  This file is part of the UPX executable compressor.
*
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

NBPW=  4
#include "arch/mips/r3000/macros.ash"
#include "arch/mips/r3000/bits.ash"

#define NO_WANT_MMAP 1
#define NO_WANT_CLOSE 1
#define NO_WANT_EXIT 1
#define NO_WANT_MPROTECT 1
#define NO_WANT_WRITE 1

        .set mips1
        .set noreorder
        .set noat
        .altmacro

sz_Ehdr= 52
e_type= 16
ET_EXEC= 2
sz_Phdr= 32

sz_b_info= 12
  sz_unc= 0
  sz_cpr= 4

sz_l_info= 12
sz_p_info= 12

sz_auxv= 8
a_type = 0  # Elf32_auxv_t
a_val  = 4

__NR_Linux = 4000
__NR_brk      =  45+ __NR_Linux
__NR_close    =   6+ __NR_Linux
__NR_exit     =   1+ __NR_Linux
__NR_ftruncate=  93+ __NR_Linux
__NR_getpid=     20+ __NR_Linux
__NR_lseek=      19+ __NR_Linux
__NR_memfd_create=354+__NR_Linux
__NR_mmap=       90+ __NR_Linux
__NR_mkdir=      39+ __NR_Linux
__NR_mprotect = 125+ __NR_Linux
__NR_msync =    144 + __NR_Linux
__NR_munmap   =  91+ __NR_Linux
__NR_oldstat=    18+ __NR_Linux
__NR_open     =   5+ __NR_Linux
__NR_read     =   3+ __NR_Linux
__NR_readlink =  85+ __NR_Linux
__NR_uname=     122+ __NR_Linux
__NR_unlink=     10+ __NR_Linux
__NR_write    =   4+ __NR_Linux

PATHSIZE=4096
OVERHEAD=2048
#include "../src/MAX_ELF_HDR.S"

MAP_PRIVATE=  0x002
// see "#define __MAP_ANONYMOUS 0x0800" in  mips-linux-gnu/libc/usr/include/bits/mman.h
MAP_ANONYMOUS=0x800  # not same as i386
PROT_READ= 1

O_RDONLY= 0

sp_frame= 0x20
F_PMASK= 4*NBPW
F_fd=    5*NBPW
F_ADRU=  6*NBPW
F_LENU=  7*NBPW
  // The above 4 registers are passed on stack to unfolded code.
a4_sys=  4*NBPW
a5_sys=  5*NBPW

unmap_all_pages=   (1<<1)

// C-language offers 8 register args; syscall offers only 4
#define a4  t0
#define a5  t1

//ra             31
//s8 AVAIL       30  /* s8 */
//sp             29  /* hardware */
#define r_PMASK  28  /* gp */
//k1             27  /* trashed by syscall */
//k0             26  /* trashed by syscall */
//t9, jp         25  /* trashed by syscall ? */
//t8             24  /* trashed by syscall ? */
//s7 AVAIL       23  /* s7 */  # saved temp for /proc/self/exe
#define r_auxv   22  /* s6 */
#define r_elfa   21  /* s5 */
#define r_FOLD   20  /* s4 */
  #define r_auxe   20  /* s4 */
#define r_obinfo 19  /* s3 */  /* previously r_LENU */
//s2 AVAIL       18  /* s2 */  # previously r_ADRU
#define r_LENX   17  /* s1 */
#define r_ADRX   16  /* s0 */

page_mask: .word 0  # set by elf-entry.S
upxfn_path: .word 0  # set by elf-entry.S

// KNOWN OFFSET == 2*NBPW == 8
fold_begin:  b L05; nop

// KNOWN OFFSET == 4*NBPW == 16
get4unal: .globl get4unal
        lwr v0,0(a0)  # little-endian (default)
        ret
          lwl v0,3(a0)

        lwl v0,0(a0)  # big-endian (replacement)
        ret
          lwr v0,3(a0)

/* In:
    r_ADRX,r_LENX,r_elfa,r_auxv,r_PMASK
    sp= -sp_frame{%,%,%,%,PMASK,%,ADRU,LENU}, {argc,argv...,0,env...,0,auxv...,0,0,strings}
*/
L05:
       lw $r_obinfo,-4($r_FOLD)  // O_BINFO | is_ptinerp | unmap_all_pages
         nop
       andi at,$r_obinfo,unmap_all_pages
       bnez at,0f
         move v0,sp
        addiu sp,(~0<<4)&-(NBPW+ 4+ PATHSIZE - sp_frame)  # alloca: new envp[0], "   =", buffer
0:

#define TMP $25
        move v1,sp
L10:  # copy until auxv
        lw TMP,0(v0); addiu v0,NBPW
        sw TMP,0(v1); addiu v1,NBPW
        bne v0,$r_auxv,L10
          andi at,$r_obinfo,unmap_all_pages
        bnez at,L30
          addiu t1,v1,-NBPW  // new envp goes here
        sw zero,(v1); addiu v1,NBPW  // new terminator for envp
L20:
        move $r_auxv,v1  // new auxv

L25:  // copy auxv
        lw TMP,0(v0); lw t0,NBPW(v0); addiu v0,sz_auxv
        sw TMP,0(v1); sw t0,NBPW(v1); addiu v1,sz_auxv
        bnez TMP,L25  # AT_NULL: stop when v0= &auxv[N]
          move $r_auxe,v1  // end of new auxv
        andi at,$r_obinfo,unmap_all_pages
        bnez at,no_pse_env
          li TMP,' '
        sw v1,0(t1)  # new env var
        sb TMP,0(v1)  # endian neutral!
        sb TMP,1(v1)
        sb TMP,2(v1)
        li TMP,'='
        sb TMP,3(v1)
        addiu s7,v1,4  # &buf[0]

        bal L30
          sw ra,F_fd(sp)  # "/proc/self/exe"
        .asciz "/proc/self/exe"
        .balign 4

get_page_mask: .globl get_page_mask
Lget_page_mask:
        move v1,ra
        bal 5f  // ra= 0f
          lw v0,(ra)
0:
        .word page_mask - 0b
5:
          nop
        addu v0,ra
        jr v1
          lw v0,(v0)

get_upxfn_path: .globl get_upxfn_path  // char * (*)(void)
        move v1,ra
        bal 5f  // ra= 0f
          lw at,(ra)
0:
        .word upxfn_path - 0b
5:
          nop
        addu at,ra  // &upxfn_path
        lw v0,(at)  // offset
          nop
        beqz v0,9f  // null string
          addu v0,at
        jr v1
          addiu v0,-1*NBPW
9:
        jr v1
          move v0,$0

close: .globl close
        b sysgo; li v0,__NR_close

L30:
        li a1,O_RDONLY
        move a0,ra  # "/proc/self/exe"
        li v0,__NR_open; syscall

        li a2,PATHSIZE-1
        move a1,s7  # &buf[0]
        lw a0,F_fd(sp)  # "/proc/self/exe"
        sw v0,F_fd(sp)  # result of __NR_open
        li v0,__NR_readlink; syscall
        bltz a3,0f
          addu TMP,a1,v0
        sb $0,(TMP)  # null terminate the path
0:
no_pse_env:
        addiu sp,-MAX_ELF_HDR_32  # alloca
        move a4,sp  # &tmp_ehdr
        move a3,$r_auxv  # new &auxv[0]
        move a2,$r_elfa  # &Elf32_Ehdr of stub
        move a1,$r_LENX  # total_size

        bal upx_main  # remember that Makefile 'cat' all *.[sS]
          move a0,$r_ADRX

/* entry= upx_main(b_info *a0, total_size a1, Elf32_Ehdr *a2, Elf32_Auxv_t *a3,
                Elf32_Ehdr *tmp_ehdr
*/
        addiu sp,MAX_ELF_HDR_32  # un-alloca
        move s8,v0  # &entry

p_vaddr= 2*NBPW
p_memsz= 5*NBPW
// Discard pages of compressed data (includes [ADRX,+LENX) )
        lw a1,p_memsz+sz_Phdr+sz_Ehdr($r_elfa)  // Phdr[C_TEXT= 1].p_memsz
        move a0,$r_elfa  // hi elfaddr
        //lh v0,e_type($r_elfa); li at,ET_EXEC; bne at,v0,1f
        li v0,__NR_brk; syscall
1:
        li v0,__NR_munmap; syscall

// Map 1 page of /proc/self/exe so that munmap does not remove all references
        lw   a4,F_fd(sp)
        andi at,$r_obinfo,unmap_all_pages
        bnez at,no_map_pse
          lw   a4,F_fd(sp)
            move a5,$0  // offset
        bltz a4,no_map_pse
          sw a4,a4_sys(sp)
          sw a5,a5_sys(sp)
        li   a3,MAP_PRIVATE
        li   a2,PROT_READ
        neg  a1,$r_PMASK  // PAGE_SIZE
        move a0,$0  // addr
        li v0,__NR_mmap; syscall
// close /proc/self/exe
        lw a0,a4_sys(sp)  // fd
        li v0,__NR_close; syscall
no_map_pse:
        lw a1,F_LENU(sp)  # prepare for munmap() at escape hatch
        lw a0,F_ADRU(sp)
        addiu sp,sp,sp_frame

/* Workaround suspected glibc bug: elf/rtld.c assumes uninit local is zero.
   2007-11-24 openembedded.org mipsel-linux 2.6.12.6/glibc 2.3.2

   Also early uClibc/ldso/ldso/ldso.c function _dl_get_ready_to_run() forgot
     _dl_memset(app_tpnt, 0, sizeof(*app_tpnt));
   leaving garbage in
            if (app_tpnt->dynamic_info[DT_TEXTREL]) {
   leading to SIGSEGV.  Fixed in [git blame:]
27d501fdbf (Denis Vlasenko           2009-01-10 21:02:48 +0000
*/
        move TMP,sp
        addiu sp, -0x380  # estimated stack bound of upx_main and below
0:
        addiu sp,NBPW
        bne sp,TMP,0b
          sw $0,-NBPW(sp)

        lw TMP,-sz_auxv+ a_val($r_auxe)  // last .a_val
          nop  # needed? allegedly MIPS R3000 provides load delay in hardware when needed
        beqz TMP,L40  # could not make escape hatch
          nop  # even R3000 requires branch delay
        jr TMP  # goto munmap escape hatch: [syscall; jr s8; nop]
          li v0,__NR_munmap
L40:
        jr s8  # omit munmap
          nop

  section SYSCALLS; .set noreorder

Pprotect: .globl Pprotect
        addiu sp,-2*NBPW; sw ra,0*NBPW(sp)
        bal Lget_page_mask
          nop
        not v0,v0  # fragment mask
        lw ra,0*NBPW(sp)
        and TMP,a0,v0
        sub a0,TMP
        add a1,TMP
        li v0,__NR_mprotect; syscall
        jr ra
          addiu sp,2*NBPW

Psync: .globl Psync
        addiu sp,-2*NBPW; sw ra,0*NBPW(sp)
        bal Lget_page_mask
          nop
        not v0,v0  # fragment mask
        lw ra,0*NBPW(sp)
        and TMP,a0,v0
        sub a0,TMP
        add a1,TMP
        li v0,__NR_msync; syscall
        jr ra
          addiu sp,2*NBPW

my_bkpt: .globl my_bkpt
        break  # my_bkpt
        jr ra
          nop

// mips-linux-gnu/libc/uclibc/lib/libgcc_s.so.1: __clear_cache is a no-op  [??]
//
// Subbsumed by [write() +] mmap() on PROT_EXEC after  memfd_create().
// Also, are the parameters (lo, hi) or (lo, size)?
// MIPSr2 has "synci offset(reg)" for one cache line.
// but then you need "rdhwr reg,hwr_synci_step" to find CACHELINE size,
// or safe default of 16 bytes; most are least 32 bytes.
//__clear_cache: .globl __clear_cache
//        j ra
//          nop

memset: .globl memset  // (dst, val, n)
        beqz a2,9f
          move v0,a0
0:
        sb a1,(a0)
        la a2,-1(a2)
        bnez a2,0b
          la a0,1(a0)
9:
        j ra
          nop

memcpy: .globl memcpy  // (dst, src, n)
        beq $0,a2,9f
          move v0,a0
0:
        lb at,(a1); la a1, 1(a1)
        sb at,(a0); la a2,-1(a2)
        bnez a2,0b
          la a0,1(a0)
9:
        j ra
          nop

mempcpy: .globl mempcpy  // (dst, src, n)
        beq $0,a2,9f
          nop
0:
        lb at,(a1); la a1, 1(a1)
        sb at,(a0); la a2,-1(a2)
        bnez a2,0b
          la a0,1(a0)
9:
        j ra
          move v0,a0

mmap_privanon: .globl mmap_privanon
        ori a3,a3,MAP_PRIVATE|MAP_ANONYMOUS
        li t0,-1  # fd
        li t1,0   # offset
mmap: .globl mmap
        addiu sp,sp,-sp_frame
        sw a4,a4_sys(sp)
        sw a5,a5_sys(sp)
        li v0,__NR_mmap; syscall
        lw a4,a4_sys(sp)
        lw a5,a5_sys(sp)
        b sysret
          addiu sp,sp,sp_frame

sysgo:  // src/mipsel.r3000-linux.elf-fold.S
sysgo2:
        syscall
sysret:
        bgez a3,sysOK
          nop
        move v0,a3  // -errno:  < 0, and > 0xfffff000
sysOK:
        jr ra
          nop

exit: .globl exit
        b sysgo; li v0,__NR_exit
brk: .globl brk
        b sysgo; li v0,__NR_brk
ftruncate: .globl ftruncate
        b sysgo; li v0,__NR_ftruncate
getpid: .globl getpid
        b sysgo; li v0,__NR_getpid
lseek: .globl lseek
        b sysgo; li v0,__NR_lseek
memfd_create: .globl memfd_create
        b sysgo; li v0,__NR_memfd_create
mkdir: .globl mkdir
        b sysgo; li v0,__NR_mkdir
mprotect: .globl mprotect
        b sysgo; li v0,__NR_mprotect
msync: .globl msync
        b sysgo; li v0,__NR_msync
munmap: .globl munmap
        b sysgo; li v0,__NR_munmap
stat: .globl stat
        b sysgo; li v0,__NR_oldstat  // WARNING: oldstat
open: .globl open
        b sysgo; li v0,__NR_open
read: .globl read
        b sysgo; li v0,__NR_read
readlink: .globl readlink
        b sysgo; li v0,__NR_readlink
uname: .globl uname
        b sysgo; li v0,__NR_uname
unlink: .globl unlink
        b sysgo; li v0,__NR_unlink
write: .globl write
        b sysgo; li v0,__NR_write

/* vim:set ts=8 sw=8 et: */
