@  arm-linux.elf-fold.S -- linkage to C code to process Elf binary
@
@  This file is part of the UPX executable compressor.
@
@  Copyright (C) 2000-2025 John F. Reiser
@  All Rights Reserved.
@
@  UPX and the UCL library are free software; you can redistribute them
@  and/or modify them under the terms of the GNU General Public License as
@  published by the Free Software Foundation; either version 2 of
@  the License, or (at your option) any later version.
@
@  This program is distributed in the hope that it will be useful,
@  but WITHOUT ANY WARRANTY; without even the implied warranty of
@  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
@  GNU General Public License for more details.
@
@  You should have received a copy of the GNU General Public License
@  along with this program; see the file COPYING.
@  If not, write to the Free Software Foundation, Inc.,
@  59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
@
@  Markus F.X.J. Oberhumer              Laszlo Molnar
@  <markus@oberhumer.com>               <ezerotven+github@gmail.com>
@
@  John F. Reiser
@  <jreiser@users.sourceforge.net>
@

NBPW= 4

#define ARMEL_EABI4 1
#include "arch/arm/v4a/macros.S"

sz_Elf32_Ehdr = 13*NBPW
e_type= 16
ET_EXEC= 2
sz_Elf32_Phdr =  8*NBPW
p_vaddr= 2*NBPW
p_memsz= 5*NBPW
sz_l_info = 12
sz_p_info = 12
sz_b_info = 12
  sz_unc= 0
  sz_cpr= 4
  b_method= 8

MAP_ANONYMOUS= 0x20
MAP_PRIVATE=   0x02
MAP_FIXED=     0x10

PROT_READ=     0x1

O_RDONLY=       0

PATHMAX=  4096

PATH_MAX= 4096

#ifndef DEBUG  /*{*/
#define DEBUG 0
#define TRACE_REGS r0-r12,r14,r15
#endif  /*}*/

#define OVERHEAD 2048
#define call bl
#include "MAX_ELF_HDR.S"

ZERO=       . - 3*NBPW
page_mask=  . - 3*NBPW; .globl page_mask
qflg_data = . - 2*NBPW  // QNX vs Linux: MAP_PRIVATE | MAP_ANONYMOUS
upxfn_path= . - 1*NBPW  // displacement from "zero"

arg1  .req r0
arg2  .req r1
arg3  .req r2
arg4  .req r3
arg5  .req r4
arg6  .req r5

fold_begin:  // enter here
        b L05  // put page_mask and qflg_data within short-displacement of uses

get_page_mask: .globl get_page_mask
        ldr r0,page_mask
        ret

get_upxfn_path: .globl get_upxfn_path  // char * (*)(void)
    adr r1,ZERO
    ldr r0,[r1,#upxfn_path - ZERO]  // offset(upxfn_path)
    cmp r0,#0; beq 1f  // nullptr
    add r0,r0,r1  // &path
1:
    ret

// Sometimes Linux enforces page-aligned address
Pprotect: .globl Pprotect
mprotect: .globl mprotect
        ldr r12,page_mask
        bic r12,arg1,r12  // lo frag
        sub arg1,arg1,r12  // page align lo end
        add arg2,arg2,r12
        do_sys __NR_mprotect; ret

Psync: .globl Psync
        ldr r12,page_mask
        bic r12,arg1,r12  // lo frag
        sub arg1,arg1,r12  // page align lo end
        add arg2,arg2,r12
        do_sys __NR_msync; ret

mmap_privanon: .globl mmap_privanon
        stmdb sp!,{r4,r5,lr}
        ldr r4,qflg_data  @ MAP_PRIVATE|MAP_ANON for Linux; MAP_PRIVANON for QNX
        mov arg6,#0  @ offset= 0
        orr arg4,arg4,r4  @ combine with input (such as MAP_FIXED)
        mvn arg5,#0  @ fd= -1
        b mmap_do

// __NR_oldmmap gets ENOSYS!  Must use __NR_mmap64 with all args in registers
// Called from C (5th and 6th arg on stack), so must preserve r4 and r5
mmap: .globl mmap
        stmdb sp!,{r4,r5,lr}  // called from C: only 4 args in registers
        ldr arg6,[sp,#4*NBPW]
        ldr arg5,[sp,#3*NBPW]
        mov arg6,arg6,lsr #12  @ FIXME?  convert to page offset in file
mmap_do: // sp: saved r4,r5,lr
        ldr r12,page_mask
        bic r12,arg1,r12  // lo frag
        sub arg1,arg1,r12  // page align lo end
        add arg2,arg2,r12
        do_sys __NR_mmap2
        ldmia sp!,{r4,r5,pc}

proc_self_exe: .asciz "/proc/self/exe"; .balign 4

// In:  sp/ F_ADRX,F_LENX,F_ELFA,F_ADRU,F_LENU,F_R0,F_R1,%F_ENTR,F_argc
//   [ADRX, +LENX) = extent of compressed program
//   [ADRU, +LENU) = params to munmap unfolded stub
F_ADRX=  0*NBPW
  F_obinfo= F_ADRX  // unmap_all_pages in lo bits
F_LENX=  1*NBPW
F_ELFA=  2*NBPW
F_ADRU=  3*NBPW
F_LENU=  4*NBPW
F_R0=    5*NBPW
F_R1=    6*NBPW
F_ENTR=  7*NBPW
  F_qflg = F_ENTR  // QNX mmap flags
F_ARGC=  8*NBPW

is_ptinterp=     (1<<0)
unmap_all_pages= (1<<1)

/* In:
   r4= ADRX | unmap_all_pages
   r5= LENX
sp/ ADRX|uap,LENX,ELFA,ADRU,LENU,r0,r1,%entry, argc,argv,0,envp,0,auxv
        (ADRX,LENX) = extent of compressed program
        (ADRU,LENU) = params to munmap unfolded stub
*/

L05:
        ldmia sp!,{r4,r5,r6,r7,r8,r9,r10,r11,r12}  // F_ADRX .. F_ARGC
        mov r1,sp  @ src
        tst r4,#unmap_all_pages; bne 0f; sub sp,sp,#PATH_MAX; 0:
        mov r0,sp  @ dst
        stmdb sp!,{r4,r5,r6,r7,r8,r9,r10,r11,r12}

0: // copy argv down
        ldr r3,[r1],#NBPW; cmp r3,#0
        str r3,[r0],#NBPW; bne 0b
     mov r4,r0  @ &new_env[0]
     ldr r2,[sp,#F_obinfo]; tst r2,#unmap_all_pages; bne 0f  @ no new_env
        str r3,[r0],#NBPW  @ space for new_env[0]
0:

0: // copy env down
        ldr r3,[r1],#NBPW; cmp r3,#0
        str r3,[r0],#NBPW; bne 0b
     mov r5,r1  @ &orig_auxv[0]

0: // copy auxv down
        ldmia r1!,{r2,r3}; cmp r2,#0
        stmia r0!,{r2,r3}; bne 0b
     mov r6,r1  @ &orig_auxv[end]; also &old_strings
     mov r9,r0  @ &down_auxv[end]
     ldr r2,[sp,#F_obinfo]; tst r2,#unmap_all_pages; bne no_pse_env
pse_env:
        adr arg1,proc_self_exe
        mov arg2,#O_RDONLY
        do_sys7t __NR_open  // ENOENT is OK
r_pse .req r8
        mov r_pse,r0

        mov arg3,#PATH_MAX
        mov arg2,r9  @ buffer
        adr arg1,proc_self_exe
        sub arg3,arg3,#1  @ room for null terminator
        do_sys7t __NR_readlink  // ENOENT is OK
        cmn r0,#1<<12
        movcs r1,arg1  @ FIXME?  "/proc/self/exe"
        movcs r0,#14  @ strlen("/proc/self/exe")
link_ok:
        add r2,r1,r0  @ end
        mov r0,r6  @ &old_strings
        mov  r3,#0;        strb r3,[r0,#-1]!  @ terminate link name
0: // copy backwards to beginning
        ldrb r3,[r2,#-1]!; strb r3,[r0,#-1]!
        cmp r1,r2; bne 0b
        mov  r3,#'=';      strb r3,[r0,#-1]!
        mov  r3,#' ';      strb r3,[r0,#-1]!
                           strb r3,[r0,#-1]!
                           strb r3,[r0,#-1]!
        str r0,[r4]  @ new_env[0]

// preserve 8-byte alignment of stack pointer
        mov r0,r0,lsr #2
        mov r0,r0,lsl #2  @ &new_strings
        eor r3,r6,r0  @ word parity with &old_strings
        and r3,r3,#NBPW  @ 0 or 4
        eor r3,r3,#NBPW  @ we add 1 new_env[0]
        sub r0,r0,r3  @ align mod 8

// copy up auxv,env,argv
        sub r3,r0,r6  @ &new_auxv[end] - &orig_auxv[end]
        add r3,r3,r5  @ &new_auxv[0] = delta +  &orig_auxv[0]
        mov r1,r9  @ &down_auxv[end]
r_auxe .req r10
        mov r_auxe,r0  @ &new_auxv[end]
0:
        ldr r2,[r1,#-4]!; cmp r1,sp
        str r2,[r0,#-4]!; bne 0b
        mov sp,r0
no_pse_env:

/* Construct arglist for upx_main */
        ldmia sp!,{arg1,arg2,arg3}  @ pop: ADRX, LENX, elfaddr
        stmdb sp!,{arg1,arg2,arg3}  @ put back
        bic arg1,arg1,#unmap_all_pages  // ADRX
r_elfa .req r9
        mov r_elfa,arg3  // save elfaddr
        //mov arg4,r3  @ auxv
        sub sp,sp,#MAX_ELF_HDR_32 + OVERHEAD  @ alloca
        stmdb sp!,{sp}  // arg5  &tmp_ehdr
        call upx_main
        add sp,sp,#NBPW  // toss arg5
        add sp,sp,#MAX_ELF_HDR_32 + OVERHEAD  @ un-alloca
        str r0,[sp,#F_ENTR]  @ entry address

// Map 1 page of /proc/self/exe so that it does not disappear
        ldr r0,[sp,#F_obinfo]; tst r0,#unmap_all_pages; bne no_map_pse
        mov arg6,#0  @ SEEK_SET offset
        mov arg5,r_pse
        stmdb sp!,{arg5,arg6}  @ arg5,arg6 C-lang calling convention
        mov arg4,#MAP_PRIVATE
        mov arg3,#PROT_READ
        ldr arg2,page_mask
        mov arg1,#0  @ any address
        sub arg2,arg1,arg2  // page_size
        call mmap  @ no error check: cannot recover
        ldmia sp!,{arg1,r1}  @ fd, offset
        call close
no_map_pse:

// Discard pages of compressed input data (includes [ADRC,+LENC) )
        //ldrb r0,[r_elfa,#e_type]; cmp r0,#ET_EXEC; bne 1f
1:
        ldr arg2,[r_elfa,#p_memsz+sz_Elf32_Phdr+sz_Elf32_Ehdr]  // Phdr[C_TEXT= 1].p_memsz
        mov arg1,r_elfa
        call munmap  // discard C_TEXT compressed data
        mov arg1,r_elfa; call brk  // also set the brk

#if 1|DEBUG  //{
/* Heuristic cache flush: sweep contiguous range to force collisions and evictions. */
        sub r12,sp,#(1<<18)  @ limit: 1/4 MB more
sweep:
        ldr r7,[sp],#-(1<<5)  @ extend stack; read allocate 32 bytes
        str r7,[sp]  @ make it dirty
        ldr r7,[sp]  @ read allocate again in case dirtying caused COW split
        cmp r12,sp; blo sweep

        add sp,sp,#(1<<18)  @ pop stack
#endif  //}

        add sp,sp,#3*NBPW  // toss F_ADRX,F_LENX,F_ELFA
        ldmia sp!,{arg1,arg2}  @ F_ADRU,F_LENU
        stmdb sp!,{r_auxe}
        mov r3,#0  @ clear registers: paranoia
        mov r4,#0
        mov r5,#0
        mov r6,#0

        mov r8,#0
        mov r9,#0
        mov r10,#0
        mov r11,#0

#if defined(ARMEL_DARWIN)  /*{*/
        mov r7,#0
        mov r12,#0xff & __NR_munmap
#elif defined(ARMEL_EABI4)  /*}{*/
        mov r12,#0
        mov r7, #0xff & __NR_munmap
#elif defined(ARM_OLDABI)  /*{*/
        mov r7,#0
        mov r12,#0
#endif  /*}*/
        ldmia sp!,{r12}  // r_auxe
        ldr pc,[r12,#NBPW -2*NBPW]  @ hatch: Elf32_auxv_t[AT_NULL@.a_type].a_val

f_unfilter:  @ (char *ptr, uint len, uint cto, uint fid)
        ptr  .req r0
        len  .req r1
        cto  .req r2  @ unused
        fid  .req r3

        t1   .req r2
        t2   .req r3
        and fid,fid,#0xff
        bic fid,fid,#1  @ 0x51 ==> 0x50
        cmp fid,#0x50  @ last use of fid
        movne pc,lr  @ no-op if not filter 0x50 or 0x51

        movs  len,len,lsr #2  @ word count
        cmpne ptr,#0
        moveq pc,lr  @ no-op if either len or ptr is 0

top_unf:
        sub len,len,#1
        ldr t1,[ptr,len,lsl #2]
        and t2,t1,#0x0f<<24
        cmp t2,   #0x0b<<24; bne tst_unf  @ not 'bl' subroutine call
        and t2,t1,#0xff<<24  @ all the non-displacement bits
        sub t1,t1,len  @ convert to word-relative displacement
        bic t1,t1,#0xff<<24  @ restrict to displacement field
        orr t1,t1,t2  @ re-combine
        str t1,[ptr,len,lsl #2]
tst_unf:
        cmp len,#0
        bne top_unf
        ret

#if DEBUG  /*{*/
TRACE_BUFLEN=512
trace:
        str lr,[sp,#(-1+ 15)*4]  @ return pc; [remember: sp is not stored]
        mov r4,sp  @ &saved_r0
        sub sp,sp,#TRACE_BUFLEN
        mov r2,sp  @ output string

        mov r1,#'\n'; bl trace_hex  @ In: r0 as label
        mov r1,#'>';  strb r1,[r2],#1

        mov r5,#3  @ rows to print
L600:  @ each row
        sub r0,r4,#TRACE_BUFLEN
        sub r0,r0,sp
        mov r0,r0,lsr #2; mov r1,#'\n'; bl trace_hex  @ which block of 8

        mov r6,#8  @ words per row
L610:  @ each word
        ldr r0,[r4],#NBPW; mov r1,#' '; bl trace_hex  @ next word
        subs r6,r6,#1; bgt L610

        subs r5,r5,#1; bgt L600

        mov r0,#'\n'; strb r0,[r2],#1
        sub r2,r2,sp  @ count
        mov r1,sp  @ buf
        mov r0,#2  @ FD_STDERR
#if defined(ARMEL_EABI4)  /*{*/
        mov r7,#__NR_write
        swi 0
#else  /*}{*/
        swi __NR_write
#endif  /*}*/
        add sp,sp,#TRACE_BUFLEN
    6   ldmia sp!,{TRACE_REGS}

trace_hex:  // In: r0=val, r1=punctuation before, r2=ptr; Uses: r3, ip
        strb r1,[r2],#1  @ punctuation
        mov r3,#NBPW*(8 -1)  @ shift count
        adr ip,hex
L620:
        mov r1,r0,lsr r3
        and r1,r1,#0xf
        ldrb r1,[ip, r1]
        strb r1,[r2],#1
        subs r3,r3,#NBPW; bge L620
        ret
hex:
        .ascii "0123456789abcdef"
#endif  /*}*/
        .unreq ptr
        .unreq len
        .unreq cto
        .unreq fid

memcpy: .globl memcpy  // void *memcpy(void *dst, void const *src, size_t len)
        cmp r2,#0; beq 9f
        mov r4,r0  // original dst
0:
        ldrb r3,[r1],#1; sub  r2,r2,#1
        strb r3,[r0],#1; bne 0b
9:
        mov r0,r4  // return original dst
        ret

memset: .globl memset  // (dst, val, n)
        cmp r2,#0; beq 9f
        mov r3,r0  // original dst
0:
        strb r1,[r0],#1
        subs r2,r2,#1
        bne 0b
9:
        mov r0,r3  // return original dst
        ret

mempcpy: .globl mempcpy  // (dst, src, n)
        cmp r2,#0; beq 9f
0:
        ldrb r3,[r1],#1; subs r2,r2,#1
        strb r3,[r0],#1; bne 0b
9:
        ret  // updated dst

  section SYSCALLS
__NR_exit  =  1 + __NR_SYSCALL_BASE
__NR_read  =  3 + __NR_SYSCALL_BASE
__NR_write =  4 + __NR_SYSCALL_BASE
__NR_open  =  5 + __NR_SYSCALL_BASE
__NR_close =  6 + __NR_SYSCALL_BASE
__NR_unlink= 10 + __NR_SYSCALL_BASE
__NR_lseek=  19 + __NR_SYSCALL_BASE
__NR_getpid= 20 + __NR_SYSCALL_BASE
__NR_mkdir = 39 + __NR_SYSCALL_BASE  // 0x27
__NR_brk   = 45 + __NR_SYSCALL_BASE
__NR_readlink=  85 + __NR_SYSCALL_BASE  // 0x55
__NR_munmap  =  91 + __NR_SYSCALL_BASE  // 0x5b
__NR_ftruncate= 93 + __NR_SYSCALL_BASE  // 0x5d
__NR_stat=     106 + __NR_SYSCALL_BASE  // 0x6a
__NR_fsync=    118 + __NR_SYSCALL_BASE
__NR_fdatasync=148 + __NR_SYSCALL_BASE
__NR_uname=    122 + __NR_SYSCALL_BASE  // 0x7a
__NR_mprotect= 125 + __NR_SYSCALL_BASE  // 0x7d
__NR_msync=    144 + __NR_SYSCALL_BASE  // 0x90
__NR_mmap2=    192 + __NR_SYSCALL_BASE  // 0xc0
__NR_fstat=    197 + __NR_SYSCALL_BASE  // 0xc5
__NR_memfd_create= 385 + __NR_SYSCALL_BASE  // 0x181

__ARM_NR_BASE       = 0x0f0000 + __NR_SYSCALL_BASE
__ARM_NR_cacheflush = 2 + __ARM_NR_BASE

// All of these syscalls must preserve r7 (cannot use 'do_sys7t')
// because they are called from C-language upxfd_android.c

get_sys_munmap: .globl get_sys_munmap  // r0= system call instruction
#if defined(ARMEL_DARWIN)  /*{*/
        ldr r0,4*1 + munmap
#elif defined(ARMEL_EABI4)  /*}{*/
        ldr r0,4*2 + munmap
#elif defined(ARM_OLDABI)  /*}{*/
        ldr r0,4*0 + munmap
#else  /*}{*/
        mov r0,#0
#endif  /*}*/
        ret

brk:   .globl brk;   do_sys __NR_brk; ret
close: .globl close; do_sys __NR_close; ret
exit:  .globl exit;  do_sys __NR_exit
fdatasync: .globl fdatasync; do_sys __NR_fdatasync; ret
fsync: .globl fsync; do_sys __NR_fsync; ret
fstat: .globl fstat; do_sys __NR_fstat; ret
ftruncate: .globl ftruncate; do_sys __NR_ftruncate; ret
getpid:.globl getpid;do_sys __NR_getpid; ret
lseek: .globl lseek; do_sys __NR_lseek; ret
memfd_create: .globl memfd_create; do_sys2 __NR_memfd_create; ret
mkdir: .globl mkdir; do_sys __NR_mkdir; ret
munmap: .globl munmap; do_sys __NR_munmap; ret  // BEWARE: get_sys_munmap knows where 'svc' lives!
open:  .globl open;  do_sys __NR_open; ret
read:  .globl read;  do_sys __NR_read; ret
readlink: .globl readlink; do_sys __NR_readlink; ret
stat: .globl stat; do_sys __NR_stat; ret
uname: .globl uname; do_sys __NR_uname; ret
unlink:.globl unlink;do_sys __NR_unlink; ret
write: .globl write; do_sys __NR_write; ret

        .globl __clear_cache
__clear_cache:
        mov r2,#0
        do_sys2 __ARM_NR_cacheflush; ret

        .globl my_bkpt
my_bkpt:
        bkpt  // my_bkpt
        ret

#if 1|DEBUG  /*{*/

__udivsi3: .globl __udivsi3
div10: .globl div10
        mov ip,r0  @ extra copy used at end
        sub r1,r1,r1  @ hi

        mov r2,r0  @ copy lo
        adds r0,r0,r0,lsl #3   @ 9*lo
        adc  r1,r1,r1,lsl #3   @ 9*hi + C
        add  r1,r1,r2,lsr #(32 - 3)  @ bits shifted from lo to hi

        mov r2,r0  @ copy lo
        adds r0,r0,r0,lsl #4
        adc  r1,r1,r1,lsl #4
        add  r1,r1,r2,lsr #(32 - 4)  @ * 0x99

        mov r2,r0  @ copy lo
        adds r0,r0,r0,lsl #8
        adc  r1,r1,r1,lsl #8
        add  r1,r1,r2,lsr #(32 - 8)  @ * 0x9999

        mov r2,r0  @ copy lo
        adds r0,r0,r0,lsl #16
        adc  r1,r1,r1,lsl #16
        add  r1,r1,r2,lsr #(32 - 16)  @ * 0x99999999

        subs r0,r0,ip,lsl #(32 - 1)  @ - * 0x80000000
        sbc  r1,r1,ip,lsr #1         @   * 0x19999999

        adds r0,r0,ip
        adc  r0,r1,#0  @ * 0x0.1999999a
        ret

#endif  /*}*/

/* vim:set ts=8 sw=8 et: */
