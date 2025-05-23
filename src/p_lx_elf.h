/* p_lx_elf.h --

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


#pragma once
#ifndef __UPX_P_LX_ELF_H  //{
#define __UPX_P_LX_ELF_H 1

typedef upx_uint32_t u32_t;  // easier to type; more narrow
typedef upx_uint64_t u64_t;  // easier to type; more narrow

class PackLinuxElf : public PackUnix
{
    typedef PackUnix super;
public:
    PackLinuxElf(InputFile *f);
    virtual ~PackLinuxElf();
    /*virtual void buildLoader(const Filter *);*/
    virtual int getVersion() const override { return 14; } // upx-3.96 cannot unpack, for instance
    virtual bool canUnpackVersion(int version) const override { return (version >= 11); }
    virtual tribool canUnpack() override { return super::canUnpack(); } // bool, except -1: format known, but not packed

protected:
    virtual const int *getCompressionMethods(int method, int level) const override;

    // All other virtual functions in this class must be pure virtual
    // because they depend on Elf32 or Elf64 data structures, which differ.

    virtual void pack1(OutputFile *, Filter &) override = 0;  // generate executable header
    virtual int  pack2(OutputFile *, Filter &) override = 0;  // append compressed data
    virtual off_t pack3(OutputFile *, Filter &) override = 0;  // append loader
    //virtual void pack4(OutputFile *, Filter &) override = 0;  // append pack header

    virtual unsigned pack2_shlib_overlay_init(OutputFile *fo);
    virtual unsigned pack2_shlib_overlay_compress(MemBuffer &obuf,
        MemBuffer &ibuf, unsigned u_len);
    virtual unsigned pack2_shlib_overlay_write(OutputFile *fo, MemBuffer &obuf,
        unsigned hdr_u_len, unsigned hdr_c_len);

    virtual void generateElfHdr(
        OutputFile *,
        void const *proto,
        unsigned const brka
    ) = 0;
    virtual void defineSymbols(Filter const *);
    virtual void addStubEntrySections(Filter const *, unsigned m_decompr);
    virtual void unpack(OutputFile *fo) override;
    unsigned old_data_off, old_data_len;  // un_shlib

    virtual upx_uint64_t elf_unsigned_dynamic(unsigned) const = 0;
    static unsigned elf_hash(char const *) /*const*/;
    static unsigned gnu_hash(char const *) /*const*/;

protected:
    static unsigned int const asl_delta = (1u<<12);  // --android-shlib extra page
    unsigned e_type;
    unsigned e_phnum;       /* Program header table entry count */
    unsigned e_shnum;
    unsigned e_shstrndx;
    MemBuffer file_image;   // if ET_DYN investigation
    MemBuffer lowmem;  // at least including PT_LOAD[0]
    MemBuffer mb_shdr;      // Shdr might not be near Phdr
    MemBuffer mb_dt_offsets;  // file offset of various DT_ tables
    unsigned *dt_offsets;  // index by dt_table[]
    unsigned symnum_max;
    unsigned strtab_max;
    char const *dynstr;   // from DT_STRTAB

    unsigned sz_phdrs;  // sizeof Phdr[]
    unsigned sz_elf_hdrs;  // all Elf headers
    unsigned sz_pack2;  // after pack2(), before loader
    unsigned sz_pack2a;  // after pack2() of all PT_LOAD
    unsigned lg2_page;  // log2(PAGE_SIZE)
    unsigned page_size;  // 1u<<lg2_page
    bool is_pie;  // is Position-Independent-Executable (ET_DYN main program)
    unsigned is_asl;  // is Android Shared Library
    unsigned xct_off;  // shared library: file offset of SHT_EXECINSTR
    unsigned hatch_off;  // file offset of escape hatch
    unsigned o_binfo;  // offset to first b_info
    upx_off_t so_slide;
    upx_uint64_t load_va;  // PT_LOAD[0].p_vaddr
    upx_uint64_t xct_va;  // minimum SHT_EXECINSTR virtual address
    upx_uint64_t jni_onload_va;  // runtime &JNI_OnLoad
    upx_uint64_t user_init_va;
    void *user_init_rp;  // Elf32_Rel *, Elf64_Rela *, ...
    upx_uint64_t plt_va, plt_off;
    unsigned user_init_off;  // within file_image
    unsigned linfo_off;
    unsigned loader_offset;  // during de-compression

    upx_uint16_t  e_machine;
    unsigned char ei_class;
    unsigned char ei_data;
    unsigned char ei_osabi;
    unsigned char prev_method;
    char const *osabi_note;
    unsigned upx_dt_init;  // DT_INIT, DT_PREINIT_ARRAY, DT_INIT_ARRAY
    static unsigned const DT_NUM = 34;  // elf.h
    unsigned dt_table[DT_NUM];  // 1+ index of DT_xxxxx in PT_DYNAMIC

    MemBuffer mb_shstrtab;   // via ElfXX_Shdr
    char const *shstrtab;
    MemBuffer jump_slots;  // is_asl de-compression fixing
    MemBuffer buildid_data;
    MemBuffer note_body;  // concatenated contents of PT_NOTEs, if any
    unsigned note_size;  // total size of PT_NOTEs
    int o_elf_shnum; // num output Shdrs
    static const unsigned char o_shstrtab[];
};

class PackLinuxElf32 : public PackLinuxElf
{
    typedef PackLinuxElf super;
public:
    PackLinuxElf32(InputFile *f);
    virtual ~PackLinuxElf32();
protected:
    virtual void PackLinuxElf32help1(InputFile *f);
    virtual int checkEhdr(Elf32_Ehdr const *ehdr) const;
    virtual bool canPackOSABI(Elf32_Ehdr const *);
    virtual tribool canPack() override;
    virtual tribool canUnpack() override; // bool, except -1: format known, but not packed

    // These ARM routines are essentially common to big/little endian,
    // but the class hierarchy splits after this class.
    virtual void ARM_defineSymbols(Filter const *ft);
    virtual void ARM_updateLoader(OutputFile *);
    virtual int  ARM_is_QNX(void);

    virtual upx_uint64_t canPack_Shdr(Elf32_Phdr const *pload_x0);
    virtual void pack1(OutputFile *, Filter &) override;  // generate executable header
    virtual void asl_pack2_Shdrs(OutputFile *, unsigned pre_xct_top);  // AndroidSharedLibrary processes Shdrs
    virtual void asl_slide_Shdrs();  // by so_slide if above xct_off
    virtual unsigned slide_sh_offset(Elf32_Shdr *shdr);
    virtual int  pack2(OutputFile *, Filter &) override;  // append compressed data
    virtual int  pack2_shlib(OutputFile *fo, Filter &ft, unsigned pre_xct_top);
    virtual off_t pack3(OutputFile *, Filter &) override;  // append loader
    virtual void pack4(OutputFile *, Filter &) override;  // append pack header
    virtual unsigned forward_Shdrs(OutputFile *fo, Elf32_Ehdr *ehdro);
    virtual void unpack(OutputFile *fo) override;
    virtual void un_asl_dynsym(unsigned orig_file_size, OutputFile *);
    virtual void un_shlib_1(
        OutputFile *const fo,
        MemBuffer &o_elfhdrs,
        unsigned &c_adler,
        unsigned &u_adler,
        unsigned const orig_file_size
    );
    virtual void un_DT_INIT(
        unsigned old_dtinit,
        Elf32_Phdr const *phdro,
        Elf32_Phdr const *dynhdr,  // in phdri
        OutputFile *fo
    );
    virtual void unRel32(unsigned dt_rel, Elf32_Rel *rel0, unsigned relsz,
        MemBuffer &membuf, unsigned const load_off, OutputFile *fo);

    virtual void generateElfHdr(
        OutputFile *,
        void const *proto,
        unsigned const brka
    ) override;
    virtual void defineSymbols(Filter const *) override;
    virtual void buildLinuxLoader(
        upx_byte const *const proto,  // assembly-only sections
        unsigned const szproto,
        upx_byte const *const fold,  // linked assembly + C section
        unsigned const szfold,
        Filter const *ft
    );
    virtual off_t getbrk(const Elf32_Phdr *phdr, int e_phnum) const;
    virtual void patchLoader() override;
    virtual void updateLoader(OutputFile *fo) override;
    virtual unsigned find_LOAD_gap(Elf32_Phdr const *const phdri, unsigned const k,
        unsigned const e_phnum);
    virtual off_t getbase(const Elf32_Phdr *phdr, int e_phnum) const;
    bool calls_crt1(Elf32_Rel const *rel, int sz);

    virtual Elf32_Sym const *elf_lookup(char const *) const;
    virtual unsigned elf_get_offset_from_address(unsigned) const;
    virtual unsigned elf_get_offset_from_Phdrs(unsigned, Elf32_Phdr const *phdr0) const;
    virtual Elf32_Phdr const *elf_find_Phdr_for_va(unsigned addr, Elf32_Phdr const *phdr, unsigned phnum);
    Elf32_Phdr const *elf_find_ptype(unsigned type, Elf32_Phdr const *phdr0, unsigned phnum);
    Elf32_Shdr const *elf_find_section_name(char const *) const;
    Elf32_Shdr       *elf_find_section_type(unsigned) const;
    Elf32_Dyn        *elf_find_dynptr(unsigned) const;
    unsigned elf_find_table_size(unsigned dt_type, unsigned sh_type);
    void sort_DT32_offsets(Elf32_Dyn const *const dynp0);

    int is_LOAD(Elf32_Phdr const *phdr) const;  // beware confusion with (1+ LO_PROC)
    unsigned check_pt_load(Elf32_Phdr const *);
    unsigned check_pt_dynamic(Elf32_Phdr const *);
    void invert_pt_dynamic(Elf32_Dyn const *, unsigned dt_filesz);
    void *elf_find_dynamic(unsigned) const;
    Elf32_Dyn const *elf_has_dynamic(unsigned) const;
    virtual upx_uint64_t elf_unsigned_dynamic(unsigned) const override;
    unsigned find_dt_ndx(unsigned rva);
    virtual int adjABS(Elf32_Sym *sym, unsigned delta);
    void add_phdrx(Elf32_Phdr const *);

    char const *get_str_name(unsigned st_name, unsigned symnum) const;
    char const *get_dynsym_name(unsigned symnum, unsigned relnum) const;
protected:
    Elf32_Ehdr  ehdri; // from input file
    Elf32_Phdr *phdri; // for  input file
    Elf32_Shdr *shdri; // from input file
    Elf32_Shdr *shdro; // for  output file
    static unsigned const END_PHDRX = 5;
    Elf32_Phdr const *phdrx[END_PHDRX];  // "extra" arch-specific Phdr
    unsigned n_phdrx;  // number actually used
    unsigned sz_phdrx;  // total size of bodies
    unsigned e_phoff;
    unsigned e_shoff;
    unsigned sz_dynseg;  // PT_DYNAMIC.p_memsz
    unsigned n_jmp_slot;
    unsigned plt_off;
    unsigned page_mask;  // AND clears the offset-within-page

    Elf32_Dyn          *dynseg;   // from PT_DYNAMIC
    unsigned int const *hashtab, *hashend;  // from DT_HASH
    unsigned int const *gashtab, *gashend;  // from DT_GNU_HASH
    Elf32_Sym          *dynsym;   // DT_SYMTAB; 'const' except [0] for decompressor
    Elf32_Sym    const *jni_onload_sym;

    Elf32_Shdr       *sec_strndx;
    Elf32_Shdr const *sec_dynsym;
    Elf32_Shdr const *sec_dynstr;
    Elf32_Shdr       *sec_arm_attr;  // SHT_ARM_ATTRIBUTES;

    packed_struct(cprElfHdr1) {
        Elf32_Ehdr ehdr;
        Elf32_Phdr phdr[1];
        l_info linfo;
    };

    packed_struct(cprElfHdr2) {
        Elf32_Ehdr ehdr;
        Elf32_Phdr phdr[2];
        l_info linfo;
    };

    packed_struct(cprElfHdr3) {
        Elf32_Ehdr ehdr;
        Elf32_Phdr phdr[3];
        l_info linfo;
    };

    packed_struct(cprElfHdr4) {
        Elf32_Ehdr ehdr;
        Elf32_Phdr phdr[4];
        l_info linfo;
    };

    packed_struct(cprElfHdrNetBSD) {
        Elf32_Ehdr ehdr;
        Elf32_Phdr phdr[4];
        unsigned char notes[512];
    };

    cprElfHdrNetBSD elfout;

    packed_struct(cprElfShdr3) {
        Elf32_Shdr shdr[3];
    };

    cprElfShdr3 shdrout;

    struct Elf32_Nhdr {
        unsigned namesz;
        unsigned descsz;
        unsigned type;
        //unsigned char body[0];
    };

    static void compileTimeAssertions() {
        COMPILE_TIME_ASSERT(sizeof(cprElfHdr1) == 52 + 1*32 + 12)
        COMPILE_TIME_ASSERT(sizeof(cprElfHdr2) == 52 + 2*32 + 12)
        COMPILE_TIME_ASSERT(sizeof(cprElfHdr3) == 52 + 3*32 + 12)
        COMPILE_TIME_ASSERT(sizeof(cprElfHdrNetBSD) == 52 + 4*32 + 512)
        COMPILE_TIME_ASSERT_ALIGNED1(cprElfHdr1)
        COMPILE_TIME_ASSERT_ALIGNED1(cprElfHdr2)
        COMPILE_TIME_ASSERT_ALIGNED1(cprElfHdr3)
        COMPILE_TIME_ASSERT_ALIGNED1(cprElfHdrNetBSD)
    }
};


class PackLinuxElf64 : public PackLinuxElf
{
    typedef PackLinuxElf super;
public:
    PackLinuxElf64(InputFile *f);
    virtual ~PackLinuxElf64();
    /*virtual void buildLoader(const Filter *);*/

protected:
    virtual void PackLinuxElf64help1(InputFile *f);
    virtual int checkEhdr(Elf64_Ehdr const *ehdr) const;
    virtual tribool canPack() override;
    virtual tribool canUnpack() override; // bool, except -1: format known, but not packed

    virtual upx_uint64_t canPack_Shdr(Elf64_Phdr const *pload_x0);
    virtual void pack1(OutputFile *, Filter &) override;  // generate executable header
    virtual void asl_pack2_Shdrs(OutputFile *, unsigned pre_xct_top);  // AndroidSharedLibrary processes Shdrs
    virtual void asl_slide_Shdrs();  // by so_slide if above xct_off
    virtual unsigned slide_sh_offset(Elf64_Shdr *shdr);
    virtual int  pack2(OutputFile *, Filter &) override;  // append compressed data
    virtual int  pack2_shlib(OutputFile *fo, Filter &ft, unsigned pre_xct_top);
    virtual off_t pack3(OutputFile *, Filter &) override;  // append loader
    virtual void pack4(OutputFile *, Filter &) override;  // append pack header
    virtual unsigned forward_Shdrs(OutputFile *fo, Elf64_Ehdr *ehdro);
    virtual void unpack(OutputFile *fo) override;
    virtual void un_asl_dynsym(unsigned orig_file_size, OutputFile *);
    virtual void un_shlib_1(
        OutputFile *const fo,
        MemBuffer &o_elfhdrs,
        unsigned &c_adler,
        unsigned &u_adler,
        unsigned const orig_file_size
    );
    virtual void un_DT_INIT(
        unsigned old_dtinit,
        Elf64_Phdr const *phdro,
        Elf64_Phdr const *dynhdr,  // in phdri
        OutputFile *fo
    );
    virtual void unRela64(upx_uint64_t dt_rela, Elf64_Rela *rela0, unsigned relasz,
        upx_uint64_t const old_dtinit, OutputFile *fo);

    virtual void generateElfHdr(
        OutputFile *,
        void const *proto,
        unsigned const brka
    ) override;
    virtual void defineSymbols(Filter const *) override;
    virtual void buildLinuxLoader(
        upx_byte const *const proto,  // assembly-only sections
        unsigned const szproto,
        upx_byte const *const fold,  // linked assembly + C section
        unsigned const szfold,
        Filter const *ft
    );
    virtual off_t getbrk(const Elf64_Phdr *phdr, int e_phnum) const;
    virtual void patchLoader() override;
    virtual void updateLoader(OutputFile *fo) override;
    virtual unsigned find_LOAD_gap(Elf64_Phdr const *const phdri, unsigned const k,
        unsigned const e_phnum);
    bool calls_crt1(Elf64_Rela const *rela, int sz);

    virtual Elf64_Sym const *elf_lookup(char const *) const;
    virtual upx_uint64_t elf_get_offset_from_address(upx_uint64_t) const;
    virtual Elf64_Phdr const *elf_find_Phdr_for_va(upx_uint64_t addr, Elf64_Phdr const *phdr, unsigned phnum);
    Elf64_Phdr const *elf_find_ptype(unsigned type, Elf64_Phdr const *phdr0, unsigned phnum);
    Elf64_Shdr const *elf_find_section_name(char const *) const;
    Elf64_Shdr       *elf_find_section_type(unsigned) const;
    Elf64_Dyn        *elf_find_dynptr(unsigned) const;
    unsigned elf_find_table_size(unsigned dt_type, unsigned sh_type);
    void sort_DT64_offsets(Elf64_Dyn const *const dynp0);
    int is_LOAD(Elf64_Phdr const *phdr) const;  // beware confusion with (1+ LO_PROC)
    upx_uint64_t check_pt_load(Elf64_Phdr const *);
    upx_uint64_t check_pt_dynamic(Elf64_Phdr const *);
    void invert_pt_dynamic(Elf64_Dyn const *, upx_uint64_t dt_filesz);
    void *elf_find_dynamic(unsigned) const;
    Elf64_Dyn const *elf_has_dynamic(unsigned) const;
    virtual upx_uint64_t elf_unsigned_dynamic(unsigned) const override;
    unsigned find_dt_ndx(u64_t rva);
    virtual int adjABS(Elf64_Sym *sym, unsigned long delta);
    void add_phdrx(Elf64_Phdr const *);

    char const *get_str_name(unsigned st_name, unsigned symnum) const;
    char const *get_dynsym_name(unsigned symnum, unsigned relnum) const;
protected:
    Elf64_Ehdr  ehdri; // from input file
    Elf64_Phdr *phdri; // for  input file
    Elf64_Shdr *shdri; // from input file
    Elf64_Shdr *shdro; // for  output file
    static unsigned const END_PHDRX = 5;
    Elf64_Phdr const *phdrx[END_PHDRX];  // "extra" arch-specific Phdr
    unsigned n_phdrx;  // number actually used
    unsigned sz_phdrx;  // total size of bodies
    upx_uint64_t e_phoff;
    upx_uint64_t e_shoff;
    upx_uint64_t sz_dynseg;  // PT_DYNAMIC.p_memsz
    unsigned n_jmp_slot;
    upx_uint64_t page_mask;  // AND clears the offset-within-page

    Elf64_Dyn          *dynseg;   // from PT_DYNAMIC
    unsigned int const *hashtab, *hashend;  // from DT_HASH
    unsigned int const *gashtab, *gashend;  // from DT_GNU_HASH
    Elf64_Sym          *dynsym;   // DT_SYMTAB; 'const' except [0] for decompressor
    Elf64_Sym    const *jni_onload_sym;

    Elf64_Shdr       *sec_strndx;
    Elf64_Shdr       *sec_dynsym;
    Elf64_Shdr const *sec_dynstr;
    Elf64_Shdr       *sec_arm_attr;  // SHT_ARM_ATTRIBUTES;

    packed_struct(cprElfHdr1) {
        Elf64_Ehdr ehdr;
        Elf64_Phdr phdr[1];
        l_info linfo;
    };

    packed_struct(cprElfHdr2) {
        Elf64_Ehdr ehdr;
        Elf64_Phdr phdr[2];
        l_info linfo;
    };

    packed_struct(cprElfHdr3) {
        Elf64_Ehdr ehdr;
        Elf64_Phdr phdr[3];
        l_info linfo;
    };

    packed_struct(cprElfHdr4) {
        Elf64_Ehdr ehdr;
        Elf64_Phdr phdr[4];
        l_info linfo;
    };

    cprElfHdr4 elfout;

    packed_struct(cprElfShdr3) {
        Elf64_Shdr shdr[3];
    };

    cprElfShdr3 shdrout;

    static void compileTimeAssertions() {
        COMPILE_TIME_ASSERT(sizeof(cprElfHdr1) == 64 + 1*56 + 12)
        COMPILE_TIME_ASSERT(sizeof(cprElfHdr2) == 64 + 2*56 + 12)
        COMPILE_TIME_ASSERT(sizeof(cprElfHdr3) == 64 + 3*56 + 12)
        COMPILE_TIME_ASSERT(sizeof(cprElfHdr4) == 64 + 4*56 + 12)
        COMPILE_TIME_ASSERT_ALIGNED1(cprElfHdr1)
        COMPILE_TIME_ASSERT_ALIGNED1(cprElfHdr2)
        COMPILE_TIME_ASSERT_ALIGNED1(cprElfHdr3)
        COMPILE_TIME_ASSERT_ALIGNED1(cprElfHdr4)
    }
};

class PackLinuxElf32Be : public PackLinuxElf32
{
    typedef PackLinuxElf32 super;
protected:
    PackLinuxElf32Be(InputFile *f) : super(f) {
        bele = &N_BELE_RTP::be_policy;
        PackLinuxElf32help1(f);
    }
};

class PackLinuxElf32Le : public PackLinuxElf32
{
    typedef PackLinuxElf32 super;
protected:
    PackLinuxElf32Le(InputFile *f) : super(f) {
        bele = &N_BELE_RTP::le_policy;
        PackLinuxElf32help1(f);
    }
};

class PackLinuxElf64Le : public PackLinuxElf64
{
    typedef PackLinuxElf64 super;
protected:
    PackLinuxElf64Le(InputFile *f) : super(f) {
        lg2_page=16;
        page_size=1u<<lg2_page;
        bele = &N_BELE_RTP::le_policy;
        PackLinuxElf64help1(f);
    }
};

class PackLinuxElf64Be : public PackLinuxElf64
{
    typedef PackLinuxElf64 super;
protected:
    PackLinuxElf64Be(InputFile *f) : super(f) {
        lg2_page=16;
        page_size=1u<<lg2_page;
        bele = &N_BELE_RTP::be_policy;
        PackLinuxElf64help1(f);
    }
};


/*************************************************************************
// linux/elf64amd
**************************************************************************/

class PackLinuxElf64amd : public PackLinuxElf64Le
{
    typedef PackLinuxElf64Le super;
public:
    PackLinuxElf64amd(InputFile *f);
    virtual ~PackLinuxElf64amd();
    virtual int getFormat() const override { return UPX_F_LINUX_ELF64_AMD64; }
    virtual const char *getName() const override { return "linux/amd64"; }
    virtual const char *getFullName(const options_t *) const override { return "amd64-linux.elf"; }
    virtual const int *getFilters() const override;
protected:
    virtual void pack1(OutputFile *, Filter &) override;  // generate executable header
    virtual void buildLoader(const Filter *) override;
    virtual Linker* newLinker() const override;
    virtual void defineSymbols(Filter const *) override;
};

class PackLinuxElf64arm : public PackLinuxElf64Le
{
    typedef PackLinuxElf64Le super;
public:
    PackLinuxElf64arm(InputFile *f);
    virtual ~PackLinuxElf64arm();
    virtual int getFormat() const override { return UPX_F_LINUX_ELF64_ARM64; }
    virtual const char *getName() const override { return "linux/arm64"; }
    virtual const char *getFullName(const options_t *) const override { return "arm64-linux.elf"; }
    virtual const int *getFilters() const override;
protected:
    virtual void pack1(OutputFile *, Filter &) override;  // generate executable header
    virtual void buildLoader(const Filter *) override;
    virtual Linker* newLinker() const override;
    virtual void defineSymbols(Filter const *) override;
};


/*************************************************************************
// linux/elf32ppc
**************************************************************************/

class PackLinuxElf32ppc : public PackLinuxElf32Be
{
    typedef PackLinuxElf32Be super;
public:
    PackLinuxElf32ppc(InputFile *f);
    virtual ~PackLinuxElf32ppc();
    virtual int getFormat() const override { return UPX_F_LINUX_ELF32_PPC32; }
    virtual const char *getName() const override { return "linux/ppc32"; }
    virtual const char *getFullName(const options_t *) const override { return "powerpc-linux.elf"; }
    virtual const int *getFilters() const override;
protected:
    virtual void pack1(OutputFile *, Filter &) override;  // generate executable header
    virtual void buildLoader(const Filter *) override;
    virtual Linker* newLinker() const override;
};

/*************************************************************************
// linux/elf64ppcle
**************************************************************************/

class PackLinuxElf64ppcle : public PackLinuxElf64Le
{
    typedef PackLinuxElf64Le super;
public:
    PackLinuxElf64ppcle(InputFile *f);
    virtual ~PackLinuxElf64ppcle();
    virtual int getFormat() const override { return UPX_F_LINUX_ELF64_PPC64LE; }
    virtual const char *getName() const override { return "linux/ppc64le"; }
    virtual const char *getFullName(const options_t *) const override { return "powerpc64le-linux.elf"; }
    virtual const int *getFilters() const override;
protected:
    unsigned lg2_page;  // log2(PAGE_SIZE)
    unsigned page_size;  // 1u<<lg2_page
    virtual void pack1(OutputFile *, Filter &) override;  // generate executable header
    virtual void buildLoader(const Filter *) override;
    virtual Linker* newLinker() const override;
};


class PackLinuxElf64ppc : public PackLinuxElf64Be
{
    typedef PackLinuxElf64Be super;
public:
    PackLinuxElf64ppc(InputFile *f);
    virtual ~PackLinuxElf64ppc();
    virtual int getFormat() const override { return UPX_F_LINUX_ELF64_PPC64; }
    virtual const char *getName() const override { return "linux/ppc64"; }
    virtual const char *getFullName(const options_t *) const override { return "powerpc64-linux.elf"; }
    virtual const int *getFilters() const override;
protected:
    unsigned lg2_page;  // log2(PAGE_SIZE)
    unsigned page_size;  // 1u<<lg2_page
    virtual void pack1(OutputFile *, Filter &) override;  // generate executable header
    virtual void buildLoader(const Filter *) override;
    virtual Linker* newLinker() const override;
};


/*************************************************************************
// linux/elf386
**************************************************************************/

class PackLinuxElf32x86 : public PackLinuxElf32Le
{
    typedef PackLinuxElf32Le super;
public:
    PackLinuxElf32x86(InputFile *f);
    virtual ~PackLinuxElf32x86();
    virtual int getFormat() const override { return UPX_F_LINUX_ELF_i386; }
    virtual const char *getName() const override { return "linux/i386"; }
    virtual const char *getFullName(const options_t *) const override { return "i386-linux.elf"; }
    virtual const int *getFilters() const override;
    virtual tribool canUnpack() override; // bool, except -1: format known, but not packed

protected:
    virtual void pack1(OutputFile *, Filter &) override;  // generate executable header

    virtual void buildLoader(const Filter *) override;
    virtual void addStubEntrySections(Filter const *, unsigned m_decompr) override;
    virtual Linker* newLinker() const override;
    virtual void defineSymbols(Filter const *) override;
};

class PackBSDElf32x86 : public PackLinuxElf32x86
{
    typedef PackLinuxElf32x86 super;
public:
    PackBSDElf32x86(InputFile *f);
    virtual ~PackBSDElf32x86();
    virtual int getFormat() const override = 0;
    virtual const char *getName() const override = 0;
    virtual const char *getFullName(const options_t *) const override = 0;

protected:
    virtual void pack1(OutputFile *, Filter &) override;  // generate executable header

    virtual void buildLoader(const Filter *) override;
};

class PackFreeBSDElf32x86 : public PackBSDElf32x86
{
    typedef PackBSDElf32x86 super;
public:
    PackFreeBSDElf32x86(InputFile *f);
    virtual ~PackFreeBSDElf32x86();
    virtual int getFormat() const override { return UPX_F_BSD_ELF_i386; }
    virtual const char *getName() const override { return "freebsd/i386"; }
    virtual const char *getFullName(const options_t *) const override { return "i386-freebsd.elf"; }
};

class PackNetBSDElf32x86 : public PackLinuxElf32x86
{
    typedef PackLinuxElf32x86 super;
public:
    PackNetBSDElf32x86(InputFile *f);
    virtual ~PackNetBSDElf32x86();
    virtual int getFormat() const override { return UPX_F_BSD_ELF_i386; }
    virtual const char *getName() const override { return "netbsd/i386"; }
    virtual const char *getFullName(const options_t *) const override { return "i386-netbsd.elf"; }
protected:
    virtual void buildLoader(const Filter *ft) override;
    virtual void generateElfHdr(
        OutputFile *,
        void const *proto,
        unsigned const brka
    ) override;
};

class PackOpenBSDElf32x86 : public PackBSDElf32x86
{
    typedef PackBSDElf32x86 super;
public:
    PackOpenBSDElf32x86(InputFile *f);
    virtual ~PackOpenBSDElf32x86();
    virtual int getFormat() const override { return UPX_F_BSD_ELF_i386; }
    virtual const char *getName() const override { return "openbsd/i386"; }
    virtual const char *getFullName(const options_t *) const override { return "i386-openbsd.elf"; }

protected:
    virtual void buildLoader(const Filter *ft) override;
    virtual void generateElfHdr(
        OutputFile *,
        void const *proto,
        unsigned const brka
    ) override;
};


/*************************************************************************
// linux/elfarm
**************************************************************************/

class PackLinuxElf32armLe : public PackLinuxElf32Le
{
    typedef PackLinuxElf32Le super;
public:
    PackLinuxElf32armLe(InputFile *f);
    virtual ~PackLinuxElf32armLe();
    virtual int getFormat() const override { return UPX_F_LINUX_ELF32_ARM; }
    virtual const char *getName() const override { return "linux/arm"; }
    virtual const char *getFullName(const options_t *) const override { return "arm-linux.elf"; }
    virtual const int *getFilters() const override;

protected:
    virtual const int *getCompressionMethods(int method, int level) const override;
    virtual Linker* newLinker() const override;
    virtual void pack1(OutputFile *, Filter &) override;  // generate executable header
    virtual void buildLoader(const Filter *) override;
    virtual void updateLoader(OutputFile *) override;
    virtual void defineSymbols(Filter const *) override;
};

class PackLinuxElf32armBe : public PackLinuxElf32Be
{
    typedef PackLinuxElf32Be super;
public:
    PackLinuxElf32armBe(InputFile *f);
    virtual ~PackLinuxElf32armBe();
    virtual int getFormat() const override { return UPX_F_LINUX_ELF32_ARMEB; }
    virtual const char *getName() const override { return "linux/armeb"; }
    virtual const char *getFullName(const options_t *) const override { return "armeb-linux.elf"; }
    virtual const int *getFilters() const override;

protected:
    virtual const int *getCompressionMethods(int method, int level) const override;
    virtual Linker* newLinker() const override;
    virtual void pack1(OutputFile *, Filter &) override;  // generate executable header
    virtual void buildLoader(const Filter *) override;
    virtual void updateLoader(OutputFile *) override;
    virtual void defineSymbols(Filter const *) override;
};

class PackLinuxElf32mipseb : public PackLinuxElf32Be
{
    typedef PackLinuxElf32Be super;
public:
    PackLinuxElf32mipseb(InputFile *f);
    virtual ~PackLinuxElf32mipseb();
    virtual int getFormat() const override { return UPX_F_LINUX_ELF32_MIPS; }
    virtual const char *getName() const override { return "linux/mips"; }
    virtual const char *getFullName(const options_t *) const override { return "mips-linux.elf"; }
    virtual const int *getFilters() const override;

protected:
    virtual Linker* newLinker() const override;
    virtual void pack1(OutputFile *, Filter &) override;  // generate executable header
    virtual void buildLoader(const Filter *) override;
    virtual void updateLoader(OutputFile *) override;
    virtual void defineSymbols(Filter const *) override;
};

class PackLinuxElf32mipsel : public PackLinuxElf32Le
{
    typedef PackLinuxElf32Le super;
public:
    PackLinuxElf32mipsel(InputFile *f);
    virtual ~PackLinuxElf32mipsel();
    virtual int getFormat() const override { return UPX_F_LINUX_ELF32_MIPSEL; }
    virtual const char *getName() const override { return "linux/mipsel"; }
    virtual const char *getFullName(const options_t *) const override { return "mipsel-linux.elf"; }
    virtual const int *getFilters() const override;

protected:
    virtual Linker* newLinker() const override;
    virtual void pack1(OutputFile *, Filter &) override;  // generate executable header
    virtual void buildLoader(const Filter *) override;
    virtual void updateLoader(OutputFile *) override;
    virtual void defineSymbols(Filter const *) override;
};


#endif /*} already included */

/* vim:set ts=4 sw=4 et: */
