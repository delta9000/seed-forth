\ seed/080-cc-elf.fth — ELF64 header + program header emission for our compiled output.
\
\ Layout: 64-byte ELF64_Ehdr + 56-byte Elf64_Phdr (one PT_LOAD) = 120 bytes.
\ Code begins at vaddr 0x400078, file offset 120.
\
\ Depends on 030-cc-io.fth (cc-emit-byte, cc-emit-4le, cc-emit-8le, cc-out-pos,
\ cc-out-patch-4le).

[lit] 4194304 constant cc-base-vaddr            \ 0x400000
[lit] 4194424 constant cc-entry-vaddr           \ 0x400078

\ p_filesz lives at file offset 96, 8 bytes LE.
\ p_memsz lives at file offset 104.
[lit] 96 constant cc-filesz-offset
[lit] 104 constant cc-memsz-offset

\ cc-emit-elf-header ( -- )  Emit the 120-byte header at start of cc-out-buf.
\ p_filesz left at 0 (patched in cc-finalize-elf).
: cc-emit-elf-header
  \ e_ident: 7F 45 4C 46 (magic), class=2, data=1, version=1, osabi=0, pad=8
  [lit] 127 cc-emit-byte [lit]  69 cc-emit-byte
  [lit]  76 cc-emit-byte [lit]  70 cc-emit-byte
  [lit]   2 cc-emit-byte [lit]   1 cc-emit-byte [lit]   1 cc-emit-byte
  [lit]   0 cc-emit-byte
  [lit]   0 cc-emit-byte [lit]   0 cc-emit-byte [lit]   0 cc-emit-byte [lit]   0 cc-emit-byte
  [lit]   0 cc-emit-byte [lit]   0 cc-emit-byte [lit]   0 cc-emit-byte [lit]   0 cc-emit-byte
  \ e_type=2 (ET_EXEC), e_machine=0x3E (AMD64) — both 16-bit LE
  [lit] 2 cc-emit-byte [lit] 0 cc-emit-byte
  [lit] 62 cc-emit-byte [lit] 0 cc-emit-byte
  \ e_version (32-bit LE)
  [lit] 1 cc-emit-4le
  \ e_entry (64-bit LE) = 0x400078
  cc-entry-vaddr cc-emit-8le
  \ e_phoff = 64
  [lit] 64 cc-emit-8le
  \ e_shoff = 0
  [lit] 0 cc-emit-8le
  \ e_flags
  [lit] 0 cc-emit-4le
  \ e_ehsize=64, e_phentsize=56, e_phnum=1, then 6 bytes of zero
  [lit] 64 cc-emit-byte [lit] 0 cc-emit-byte
  [lit] 56 cc-emit-byte [lit] 0 cc-emit-byte
  [lit]  1 cc-emit-byte [lit] 0 cc-emit-byte
  [lit]  0 cc-emit-byte [lit] 0 cc-emit-byte
  [lit]  0 cc-emit-byte [lit] 0 cc-emit-byte
  [lit]  0 cc-emit-byte [lit] 0 cc-emit-byte
  \ Program header (56 bytes, one PT_LOAD):
  [lit] 1 cc-emit-4le                            \ p_type = PT_LOAD
  [lit] 7 cc-emit-4le                            \ p_flags = R|W|X
  [lit] 0 cc-emit-8le                            \ p_offset = 0
  cc-base-vaddr cc-emit-8le                      \ p_vaddr = 0x400000
  cc-base-vaddr cc-emit-8le                      \ p_paddr = 0x400000
  [lit] 0 cc-emit-8le                            \ p_filesz (patched later)
  [lit] 81920 cc-emit-8le                        \ p_memsz = 0x14000
  [lit] 4096 cc-emit-8le ;                       \ p_align = 0x1000

\ cc-finalize-elf ( -- )  After codegen, patch p_filesz to current cc-out-pos.
\ We patch only the low 4 bytes — our outputs are well under 4 GiB and the
\ high 4 bytes were already emitted as zero.  Also bump p_memsz so it is at
\ least p_filesz (otherwise large outputs like the M2-Planet monolith — well
\ past the 0x14000 default — produce an invalid ELF that the kernel won't
\ load correctly).  Keep the 0x14000 minimum for small outputs that need
\ BSS-style headroom past their file image.
: cc-finalize-elf
  cc-out-pos @ cc-filesz-offset cc-out-patch-4le
  cc-out-pos @ [lit] 81920 > if,
    cc-out-pos @ cc-memsz-offset cc-out-patch-4le
  then, ;
