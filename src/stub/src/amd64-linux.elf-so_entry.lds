OUTPUT_FORMAT("elf64-x86-64", "elf64-x86-64", "elf64-x86-64")
OUTPUT_ARCH(i386:x86-64)


SECTIONS
{
  .text : {
  }
  ELFMAINX : {
    *(ELFMAINX)
    *(.text)
  }
}
