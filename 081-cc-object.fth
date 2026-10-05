\ 081-cc-object.fth — bounded ELF64/AMD64 relocatable object writer.
\ Depends only on 010-lib, 020-cc-arena, 030-cc-io. No tool subprocesses.
\ ELF layout follows the System V gABI and AMD64 psABI; see book Ch 35.
\ API symbol IDs are stable; ELF indexes are assigned locals-first at build.
\ Errors: 244 section/range/alignment, 245 capacity, 246 symbol,
\ 247 relocation, 248 file I/O. Generic output overflow remains error 21.

[lit] 0 constant cc-obj-undef
[lit] 1 constant cc-obj-text
[lit] 2 constant cc-obj-rodata
[lit] 3 constant cc-obj-data
[lit] 4 constant cc-obj-bss
[lit] 65521 constant cc-obj-abs
[lit] 0 constant cc-obj-local
[lit] 1 constant cc-obj-global
[lit] 2 constant cc-obj-weak
[lit] 0 constant cc-obj-notype
[lit] 1 constant cc-obj-object
[lit] 2 constant cc-obj-func
[lit] 3 constant cc-obj-section
[lit] 0 constant cc-obj-default
[lit] 1 constant cc-obj-internal
[lit] 2 constant cc-obj-hidden
[lit] 3 constant cc-obj-protected
[lit] 1 constant cc-obj-r64
[lit] 2 constant cc-obj-pc32
[lit] 4 constant cc-obj-plt32
[lit] 10 constant cc-obj-r32
[lit] 11 constant cc-obj-r32s

[lit] 524288 constant cc-obj-text-default-cap
variable cc-obj-text-limit
cc-obj-text-default-cap cc-obj-text-limit !
: cc-obj-text-cap ( -- bytes ) cc-obj-text-limit @ ;
[lit] 262144 constant cc-obj-section-default-cap
variable cc-obj-section-limit
cc-obj-section-default-cap cc-obj-section-limit !
: cc-obj-section-cap ( -- bytes ) cc-obj-section-limit @ ;
[lit] 1073741824 constant cc-obj-bss-cap
[lit] 2048 constant cc-obj-symbol-default-cap
variable cc-obj-symbol-limit
cc-obj-symbol-default-cap cc-obj-symbol-limit !
: cc-obj-symbol-cap ( -- entries ) cc-obj-symbol-limit @ ;
[lit] 4096 constant cc-obj-reloc-default-cap
variable cc-obj-reloc-limit
cc-obj-reloc-default-cap cc-obj-reloc-limit !
: cc-obj-reloc-cap ( -- entries ) cc-obj-reloc-limit @ ;
[lit] 65536 constant cc-obj-string-default-cap
variable cc-obj-string-limit
cc-obj-string-default-cap cc-obj-string-limit !
: cc-obj-string-cap ( -- bytes ) cc-obj-string-limit @ ;
create cc-obj-default-payload cc-obj-text-default-cap cc-obj-section-default-cap [lit] 2 * + allot
variable cc-obj-payload-buffer
cc-obj-default-payload cc-obj-payload-buffer !
: cc-obj-payload ( -- address ) cc-obj-payload-buffer @ ;
create cc-obj-default-symbols cc-obj-symbol-default-cap 1+ [lit] 64 * allot
variable cc-obj-symbols-buffer
cc-obj-default-symbols cc-obj-symbols-buffer !
: cc-obj-symbols ( -- address ) cc-obj-symbols-buffer @ ;
create cc-obj-default-relocs cc-obj-reloc-default-cap [lit] 40 * allot
variable cc-obj-relocs-buffer
cc-obj-default-relocs cc-obj-relocs-buffer !
: cc-obj-relocs ( -- address ) cc-obj-relocs-buffer @ ;
create cc-obj-default-strings cc-obj-string-default-cap allot
variable cc-obj-strings-buffer
cc-obj-default-strings cc-obj-strings-buffer !
: cc-obj-strings ( -- address ) cc-obj-strings-buffer @ ;
\ Complete original insn-attrtab.c needs 3,328,178 text bytes and 20,568
\ relocations. Round independently to whole MiB / 512-entry quanta.
[lit] 4194304 constant cc-obj-text-direct-cap
[lit] 20992 constant cc-obj-reloc-direct-cap
\ Complete original insn-output.c needs 7,772 symbols, excluding row zero,
\ and 77,487 string bytes. Round rows to 512 and string storage to 4 KiB.
[lit] 8192 constant cc-obj-symbol-direct-cap
[lit] 77824 constant cc-obj-string-direct-cap
\ Complete binutils 2.30 i386-dis.c needs 841,448 .data bytes (its opcode
\ tables); GCC's largest .rodata is 120,874. Rodata and data each get the
\ measured maximum plus 25%, rounded up to whole MiB: 2 MiB.
[lit] 2097152 constant cc-obj-section-direct-cap
variable cc-obj-direct-base
: cc-obj-direct-payload-bytes ( -- bytes )
  cc-obj-text-direct-cap cc-obj-section-direct-cap [lit] 2 * + ;
: cc-obj-direct-symbol-bytes ( -- bytes )
  cc-obj-symbol-direct-cap 1+ [lit] 64 * ;
: cc-obj-default-workspace ( -- )
  cc-obj-text-default-cap cc-obj-text-limit !
  cc-obj-section-default-cap cc-obj-section-limit !
  cc-obj-reloc-default-cap cc-obj-reloc-limit !
  cc-obj-symbol-default-cap cc-obj-symbol-limit !
  cc-obj-string-default-cap cc-obj-string-limit !
  cc-obj-default-payload cc-obj-payload-buffer !
  cc-obj-default-relocs cc-obj-relocs-buffer !
  cc-obj-default-symbols cc-obj-symbols-buffer !
  cc-obj-default-strings cc-obj-strings-buffer ! ;
: cc-obj-direct-workspace ( -- )
  cc-obj-direct-base @ 0= if,
    cc-obj-direct-payload-bytes cc-obj-reloc-direct-cap [lit] 40 * +
    cc-obj-direct-symbol-bytes + cc-obj-string-direct-cap +
    [lit] 245 cc-workspace-map cc-obj-direct-base !
  then,
  cc-obj-text-direct-cap cc-obj-text-limit !
  cc-obj-section-direct-cap cc-obj-section-limit !
  cc-obj-reloc-direct-cap cc-obj-reloc-limit !
  cc-obj-symbol-direct-cap cc-obj-symbol-limit !
  cc-obj-string-direct-cap cc-obj-string-limit !
  cc-obj-direct-base @ cc-obj-payload-buffer !
  cc-obj-direct-base @ cc-obj-direct-payload-bytes +
  dup cc-obj-relocs-buffer !
  cc-obj-reloc-direct-cap [lit] 40 * +
  dup cc-obj-symbols-buffer !
  cc-obj-direct-symbol-bytes + cc-obj-strings-buffer ! ;
\ Section metadata is nine CELLS, not an in-memory Elf64_Shdr:
\ name/type/flags/file-offset/size/link/info/alignment/entry-size.
create cc-obj-sections  [lit] 720 allot
variable cc-obj-current
variable cc-obj-nsym
variable cc-obj-nrel
variable cc-obj-nstr
variable cc-obj-shoff
variable cc-obj-local-end
variable cc-obj-initialized
\ Publication state is separate from object metadata and reset between writes.
create cc-obj-temp-path  [lit] 4096 allot
create cc-obj-temp-suffix  s, .obj-
create cc-obj-hex-digits  s, 0123456789abcdef
create cc-obj-stat-buffer  [lit] 144 allot
variable cc-obj-path
variable cc-obj-fd
variable cc-obj-written
variable cc-obj-temp-owned
variable cc-obj-temp-length
variable cc-obj-pid
variable cc-obj-ti
: cc-obj-reset-write ( -- )
  true cc-obj-fd ! [lit] 0 cc-obj-path ! [lit] 0 cc-obj-written !
  [lit] 0 cc-obj-temp-owned ! [lit] 0 cc-obj-temp-length !
  [lit] 0 cc-obj-pid ! [lit] 0 cc-obj-ti ! [lit] 0 cc-obj-temp-path c! ;

: cc-obj-sh ( section -- a )  [lit] 72 * cc-obj-sections + ;
: cc-obj-rel ( index -- a )  [lit] 40 * cc-obj-relocs + ;
: cc-obj-base ( section -- a )
  dup cc-obj-text = if, drop cc-obj-payload exit, then,
  [lit] 2 - cc-obj-section-cap * cc-obj-text-cap + cc-obj-payload + ;
: cc-obj-length ( section -- n )  cc-obj-sh [lit] 32 + @ ;
: cc-obj-zero ( a n -- )
  begin, dup while,
    over [lit] 0 swap c! swap 1+ swap 1-
  repeat, 2drop ;

\ Reject high-bit values explicitly: the library's comparisons are signed.
: cc-obj-bound ( n maximum code -- )
  >r over 0< if, r@ cc-die then,
  > if, r@ cc-die then, r> drop ;
\ IDs include reserved row zero. Check before multiplying, in either workspace.
: cc-obj-sym ( id -- a )
  dup cc-obj-symbol-cap [lit] 246 cc-obj-bound
  [lit] 64 * cc-obj-symbols + ;
: cc-obj-check-section ( section -- )
  dup [lit] 4 [lit] 244 cc-obj-bound
  0= if, [lit] 244 cc-die then, ;
: cc-obj-check-align ( n -- )
  dup [lit] 4096 [lit] 244 cc-obj-bound
  dup 0= if, [lit] 244 cc-die then,
  dup 1- and if, [lit] 244 cc-die then, ;
: cc-obj-require-init ( -- )
  cc-obj-initialized @ 0= if, [lit] 244 cc-die then, ;
: cc-obj-use ( section -- )
  cc-obj-require-init dup cc-obj-check-section cc-obj-current ! ;
: cc-obj-here ( -- offset )
  cc-obj-require-init cc-obj-current @ cc-obj-length ;
: cc-obj-room ( count -- )
  cc-obj-current @ cc-obj-bss = if,
    cc-obj-bss-cap
  else, cc-obj-current @ cc-obj-text = if,
    cc-obj-text-cap else, cc-obj-section-cap then, then,
  cc-obj-here - [lit] 245 cc-obj-bound ;

\ Reserve zeroed bytes; .bss grows in memory without backing file bytes.
: cc-obj-reserve ( count -- offset )
  dup cc-obj-room
  cc-obj-here >r
  cc-obj-current @ cc-obj-bss <> if,
    dup cc-obj-current @ cc-obj-base r@ + swap cc-obj-zero
  then,
  cc-obj-current @ cc-obj-sh [lit] 32 + +! r> ;
: cc-obj-align ( alignment -- )
  cc-obj-require-init dup cc-obj-check-align
  dup cc-obj-current @ cc-obj-sh [lit] 56 + @ > if,
    dup cc-obj-current @ cc-obj-sh [lit] 56 + !
  then,
  dup cc-obj-here + 1- over / * cc-obj-here -
  cc-obj-reserve drop ;
: cc-obj-byte ( byte -- )
  cc-obj-current @ cc-obj-bss = if, [lit] 244 cc-die then,
  [lit] 1 cc-obj-reserve cc-obj-current @ cc-obj-base + c! ;
: cc-obj-4le ( value -- )
  dup cc-obj-byte [lit] 256 / dup cc-obj-byte
  [lit] 256 / dup cc-obj-byte [lit] 256 / cc-obj-byte ;
: cc-obj-8le ( value -- )
  dup cc-obj-4le [lit] 4294967296 / cc-obj-4le ;
: cc-obj-bytes ( address count -- )
  dup cc-obj-room
  begin, dup while,
    over c@ cc-obj-byte swap 1+ swap 1-
  repeat, 2drop ;

\ A patch must fit wholly inside already emitted file-backed bytes.
variable cc-obj-patch-a
variable cc-obj-patch-n
: cc-obj-patch ( value section offset width -- )
  cc-obj-require-init cc-obj-patch-n ! >r
  dup cc-obj-check-section
  dup cc-obj-bss = if, [lit] 244 cc-die then,
  r@ over cc-obj-length [lit] 244 cc-obj-bound
  cc-obj-patch-n @ over cc-obj-length r@ - [lit] 244 cc-obj-bound
  cc-obj-base r> + cc-obj-patch-a !
  begin, cc-obj-patch-n @ while,
    dup cc-obj-patch-a @ c! [lit] 256 /
    [lit] 1 cc-obj-patch-a +! [lit] 1 cc-obj-patch-n -!
  repeat, drop ;
: cc-obj-patch-4le ( value section offset -- )  [lit] 4 cc-obj-patch ;
: cc-obj-patch-8le ( value section offset -- )  [lit] 8 cc-obj-patch ;

\ Symbol cells: string-offset, binding, type, visibility, section, value,
\ size, final ELF index. Names are copied; caller storage may be reused.
variable cc-obj-s-a
variable cc-obj-s-u
variable cc-obj-s-bind
variable cc-obj-s-type
variable cc-obj-s-vis
variable cc-obj-s-sec
variable cc-obj-s-value
variable cc-obj-s-size
variable cc-obj-s-row
: cc-obj-check-definition ( -- )
  cc-obj-s-sec @ cc-obj-abs = if, exit, then,
  cc-obj-s-sec @ [lit] 4 [lit] 246 cc-obj-bound
  cc-obj-s-sec @ 0= if,
    cc-obj-s-value @ cc-obj-s-size @ or if, [lit] 246 cc-die then,
  else,
    cc-obj-s-value @ cc-obj-s-sec @ cc-obj-length [lit] 246 cc-obj-bound
    cc-obj-s-size @ cc-obj-s-sec @ cc-obj-length cc-obj-s-value @ -
    [lit] 246 cc-obj-bound
  then, ;
: cc-obj-put-definition ( -- )
  cc-obj-s-sec @ cc-obj-s-row @ [lit] 32 + !
  cc-obj-s-value @ cc-obj-s-row @ [lit] 40 + !
  cc-obj-s-size @ cc-obj-s-row @ [lit] 48 + ! ;
: cc-obj-check-id ( id -- )
  dup cc-obj-nsym @ [lit] 246 cc-obj-bound
  0= if, [lit] 246 cc-die then, ;
: cc-obj-define ( id section value size -- )
  cc-obj-require-init cc-obj-s-size ! cc-obj-s-value ! cc-obj-s-sec !
  dup cc-obj-check-id cc-obj-sym cc-obj-s-row !
  cc-obj-s-row @ [lit] 16 + @ cc-obj-section = if,
    cc-obj-s-value @ cc-obj-s-size @ or if, [lit] 246 cc-die then,
    cc-obj-s-sec @ cc-obj-check-section
  then,
  cc-obj-check-definition cc-obj-put-definition ;
: cc-obj-symbol ( name length binding type visibility section value size -- id )
  cc-obj-require-init
  cc-obj-s-size ! cc-obj-s-value ! cc-obj-s-sec ! cc-obj-s-vis !
  cc-obj-s-type ! cc-obj-s-bind ! cc-obj-s-u ! cc-obj-s-a !
  cc-obj-nsym @ 1+ cc-obj-symbol-cap [lit] 245 cc-obj-bound
  cc-obj-s-bind @ [lit] 2 [lit] 246 cc-obj-bound
  cc-obj-s-type @ [lit] 3 [lit] 246 cc-obj-bound
  cc-obj-s-vis @ [lit] 3 [lit] 246 cc-obj-bound
  cc-obj-s-u @ cc-obj-string-cap cc-obj-nstr @ - 1- [lit] 245 cc-obj-bound
  cc-obj-check-definition
  cc-obj-s-type @ cc-obj-section = if,
    cc-obj-s-bind @ cc-obj-local <> cc-obj-s-u @ or
    cc-obj-s-value @ or cc-obj-s-size @ or if, [lit] 246 cc-die then,
    cc-obj-s-sec @ cc-obj-check-section
  then,
  cc-obj-s-u @ 0= cc-obj-s-type @ cc-obj-section <> and if,
    [lit] 246 cc-die
  then,
  [lit] 0
  begin, dup cc-obj-s-u @ < while,
    dup cc-obj-s-a @ + c@ 0= if, [lit] 246 cc-die then, 1+
  repeat, drop
  [lit] 1 cc-obj-nsym +!
  cc-obj-nsym @ cc-obj-sym cc-obj-s-row !
  cc-obj-nstr @ cc-obj-s-row @ !
  cc-obj-s-bind @ cc-obj-s-row @ [lit] 8 + !
  cc-obj-s-type @ cc-obj-s-row @ [lit] 16 + !
  cc-obj-s-vis @ cc-obj-s-row @ [lit] 24 + !
  cc-obj-put-definition
  [lit] 0
  begin, dup cc-obj-s-u @ < while,
    dup cc-obj-s-a @ + c@ cc-obj-strings cc-obj-nstr @ + c!
    [lit] 1 cc-obj-nstr +! 1+
  repeat, drop
  [lit] 0 cc-obj-strings cc-obj-nstr @ + c! [lit] 1 cc-obj-nstr +!
  cc-obj-nsym @ ;

\ RELA stores an explicit signed addend, including negative values, as 8 LE
\ bytes. The field in .text/.data is not used as an implicit addend.
variable cc-obj-r-sec
variable cc-obj-r-off
variable cc-obj-r-kind
variable cc-obj-r-sym
variable cc-obj-r-add
: cc-obj-reloc-width ( kind -- width )
  dup cc-obj-r64 = if, drop [lit] 8 exit, then,
  dup cc-obj-pc32 = over cc-obj-plt32 = or
  over cc-obj-r32 = or swap cc-obj-r32s = or
  0= if, [lit] 247 cc-die then, [lit] 4 ;
: cc-obj-reloc ( section offset kind id addend -- )
  cc-obj-require-init
  cc-obj-r-add ! cc-obj-r-sym ! cc-obj-r-kind ! cc-obj-r-off ! cc-obj-r-sec !
  cc-obj-r-sec @ cc-obj-text = cc-obj-r-sec @ cc-obj-data = or
  0= if, [lit] 247 cc-die then,
  cc-obj-r-sym @ cc-obj-check-id
  cc-obj-r-off @ cc-obj-r-sec @ cc-obj-length [lit] 247 cc-obj-bound
  cc-obj-r-kind @ cc-obj-reloc-width
  cc-obj-r-sec @ cc-obj-length cc-obj-r-off @ - [lit] 247 cc-obj-bound
  cc-obj-nrel @ 1+ cc-obj-reloc-cap [lit] 245 cc-obj-bound
  cc-obj-nrel @ cc-obj-rel >r
  cc-obj-r-sec @ r@ ! cc-obj-r-off @ r@ [lit] 8 + !
  cc-obj-r-kind @ r@ [lit] 16 + ! cc-obj-r-sym @ r@ [lit] 24 + !
  cc-obj-r-add @ r> [lit] 32 + ! [lit] 1 cc-obj-nrel +! ;

create cc-obj-shnames
[lit] 0 c, s, .text [lit] 0 c, s, .rodata [lit] 0 c,
s, .data [lit] 0 c, s, .bss [lit] 0 c,
s, .rela.text [lit] 0 c, s, .rela.data [lit] 0 c,
s, .symtab [lit] 0 c, s, .strtab [lit] 0 c, s, .shstrtab [lit] 0 c,
here cc-obj-shnames - constant cc-obj-shnames-size

\ Metadata initializer (name type flags alignment index --).
: cc-obj-sh-init
  cc-obj-sh >r r@ [lit] 56 + ! r@ [lit] 16 + !
  r@ [lit] 8 + ! r> ! ;
: cc-obj-init ( -- )
  cc-obj-reset-write
  cc-obj-sections [lit] 720 cc-obj-zero
  [lit] 0 cc-obj-nsym ! [lit] 0 cc-obj-nrel ! [lit] 1 cc-obj-nstr !
  [lit] 0 cc-obj-strings c! cc-obj-text cc-obj-current !
  [lit] 1 [lit] 1 [lit] 6 [lit] 1 [lit] 1 cc-obj-sh-init
  [lit] 7 [lit] 1 [lit] 2 [lit] 1 [lit] 2 cc-obj-sh-init
  [lit] 15 [lit] 1 [lit] 3 [lit] 1 [lit] 3 cc-obj-sh-init
  [lit] 21 [lit] 8 [lit] 3 [lit] 1 [lit] 4 cc-obj-sh-init
  [lit] 26 [lit] 4 [lit] 0 [lit] 8 [lit] 5 cc-obj-sh-init
  [lit] 37 [lit] 4 [lit] 0 [lit] 8 [lit] 6 cc-obj-sh-init
  [lit] 48 [lit] 2 [lit] 0 [lit] 8 [lit] 7 cc-obj-sh-init
  [lit] 56 [lit] 3 [lit] 0 [lit] 1 [lit] 8 cc-obj-sh-init
  [lit] 64 [lit] 3 [lit] 0 [lit] 1 [lit] 9 cc-obj-sh-init
  [lit] 7 [lit] 5 cc-obj-sh [lit] 40 + !
  [lit] 7 [lit] 6 cc-obj-sh [lit] 40 + !
  [lit] 8 [lit] 7 cc-obj-sh [lit] 40 + !
  [lit] 1 [lit] 5 cc-obj-sh [lit] 48 + !
  [lit] 3 [lit] 6 cc-obj-sh [lit] 48 + !
  [lit] 24 [lit] 5 cc-obj-sh [lit] 64 + !
  [lit] 24 [lit] 6 cc-obj-sh [lit] 64 + !
  [lit] 24 [lit] 7 cc-obj-sh [lit] 64 + !
  true cc-obj-initialized ! ;

: cc-obj-out-zero ( count -- )
  begin, dup while, [lit] 0 cc-emit-byte 1- repeat, drop ;
: cc-obj-out-bytes ( address count -- )
  begin, dup while, over c@ cc-emit-byte swap 1+ swap 1- repeat, 2drop ;
: cc-obj-out-align ( alignment -- )
  dup cc-out-pos @ + 1- over / * cc-out-pos @ - cc-obj-out-zero ;
: cc-obj-start-section ( index -- )
  cc-obj-sh >r r@ [lit] 56 + @ cc-obj-out-align
  cc-out-pos @ r> [lit] 24 + ! ;
: cc-obj-end-section ( index -- )
  cc-obj-sh >r cc-out-pos @ r@ [lit] 24 + @ - r> [lit] 32 + ! ;
: cc-obj-emit-symbol ( row -- )
  >r r@ @ cc-emit-4le
  r@ [lit] 8 + @ [lit] 16 * r@ [lit] 16 + @ or cc-emit-byte
  r@ [lit] 24 + @ cc-emit-byte
  r@ [lit] 32 + @ dup cc-emit-byte [lit] 256 / cc-emit-byte
  r@ [lit] 40 + @ cc-emit-8le r> [lit] 48 + @ cc-emit-8le ;

variable cc-obj-i
variable cc-obj-next-index
variable cc-obj-pass
: cc-obj-symbol-pass ( local? -- )
  cc-obj-pass ! [lit] 1 cc-obj-i !
  begin, cc-obj-i @ cc-obj-nsym @ <= while,
    cc-obj-i @ cc-obj-sym >r
    r@ [lit] 8 + @ 0= cc-obj-pass @ = if,
      cc-obj-next-index @ r@ [lit] 56 + ! [lit] 1 cc-obj-next-index +!
      r@ cc-obj-emit-symbol
    then,
    r> drop [lit] 1 cc-obj-i +!
  repeat, ;
: cc-obj-check-symbols ( -- )
  [lit] 1 cc-obj-i !
  begin, cc-obj-i @ cc-obj-nsym @ <= while,
    cc-obj-i @ cc-obj-sym >r
    r@ [lit] 8 + @ 0= r@ [lit] 32 + @ 0= and if,
      [lit] 246 cc-die
    then,
    r> drop [lit] 1 cc-obj-i +!
  repeat, ;
: cc-obj-emit-relocs ( target-section -- )
  cc-obj-r-sec ! [lit] 0 cc-obj-i !
  begin, cc-obj-i @ cc-obj-nrel @ < while,
    cc-obj-i @ cc-obj-rel >r
    r@ @ cc-obj-r-sec @ = if,
      r@ [lit] 8 + @ cc-emit-8le
      r@ [lit] 16 + @ cc-emit-4le
      r@ [lit] 24 + @ cc-obj-sym [lit] 56 + @ cc-emit-4le
      r@ [lit] 32 + @ cc-emit-8le
    then,
    r> drop [lit] 1 cc-obj-i +!
  repeat, ;
: cc-obj-emit-sh ( index -- )
  cc-obj-sh >r r@ @ cc-emit-4le r@ [lit] 8 + @ cc-emit-4le
  r@ [lit] 16 + @ cc-emit-8le [lit] 0 cc-emit-8le
  r@ [lit] 24 + @ cc-emit-8le r@ [lit] 32 + @ cc-emit-8le
  r@ [lit] 40 + @ cc-emit-4le r@ [lit] 48 + @ cc-emit-4le
  r@ [lit] 56 + @ cc-emit-8le r> [lit] 64 + @ cc-emit-8le ;
: cc-obj-build ( -- )
  cc-obj-require-init cc-obj-check-symbols cc-out-init [lit] 64 cc-obj-out-zero
  [lit] 1179403647 [lit] 0 cc-out-patch-4le
  [lit] 2 [lit] 4 cc-out-patch-byte
  [lit] 1 [lit] 5 cc-out-patch-byte [lit] 1 [lit] 6 cc-out-patch-byte
  [lit] 1 [lit] 16 cc-out-patch-byte [lit] 62 [lit] 18 cc-out-patch-byte
  [lit] 1 [lit] 20 cc-out-patch-byte [lit] 64 [lit] 52 cc-out-patch-byte
  [lit] 64 [lit] 58 cc-out-patch-byte [lit] 10 [lit] 60 cc-out-patch-byte
  [lit] 9 [lit] 62 cc-out-patch-byte
  [lit] 1 cc-obj-i !
  begin, cc-obj-i @ [lit] 4 < while,
    cc-obj-i @ cc-obj-start-section
    cc-obj-i @ cc-obj-base cc-obj-i @ cc-obj-length cc-obj-out-bytes
    [lit] 1 cc-obj-i +!
  repeat,
  [lit] 4 cc-obj-start-section
  \ Emit symbols first in the file so every relocation can use its ELF index.
  \ Section-table order is independent of the order of section file bytes.
  [lit] 7 cc-obj-start-section [lit] 24 cc-obj-out-zero
  [lit] 1 cc-obj-next-index ! true cc-obj-symbol-pass
  cc-obj-next-index @ dup cc-obj-local-end ! [lit] 7 cc-obj-sh [lit] 48 + !
  [lit] 0 cc-obj-symbol-pass [lit] 7 cc-obj-end-section
  [lit] 5 cc-obj-start-section cc-obj-text cc-obj-emit-relocs [lit] 5 cc-obj-end-section
  [lit] 6 cc-obj-start-section cc-obj-data cc-obj-emit-relocs [lit] 6 cc-obj-end-section
  [lit] 8 cc-obj-start-section cc-obj-strings cc-obj-nstr @ cc-obj-out-bytes
  [lit] 8 cc-obj-end-section
  [lit] 9 cc-obj-start-section cc-obj-shnames cc-obj-shnames-size cc-obj-out-bytes
  [lit] 9 cc-obj-end-section
  [lit] 8 cc-obj-out-align cc-out-pos @ dup cc-obj-shoff ! [lit] 40 cc-out-patch-8le
  [lit] 0 cc-obj-i !
  begin, cc-obj-i @ [lit] 10 < while,
    cc-obj-i @ cc-obj-emit-sh [lit] 1 cc-obj-i +!
  repeat, ;

\ Validate/build before creating a sibling temporary. Never truncate the old
\ output; only publish after every byte and close succeed. Refuse special files.
: cc-obj-check-output ( -- )
  cc-obj-path @ cc-obj-stat-buffer [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 4 syscall6
  dup [lit] 0 [lit] 2 - = if, drop exit, then,
  0= 0= if, [lit] 248 cc-die then,
  cc-obj-stat-buffer [lit] 24 + @ [lit] 61440 and [lit] 32768 <>
  if, [lit] 248 cc-die then, ;
: cc-obj-make-temp-path ( -- )
  begin, cc-obj-path @ cc-obj-temp-length @ + c@ dup while,
    cc-obj-temp-length @ [lit] 4074 >= if, [lit] 248 cc-die then,
    cc-obj-temp-path cc-obj-temp-length @ + c!
    [lit] 1 cc-obj-temp-length +!
  repeat, drop
  cc-obj-temp-length @ 0= if, [lit] 248 cc-die then,
  begin, cc-obj-ti @ [lit] 5 < while,
    cc-obj-temp-suffix cc-obj-ti @ + c@
    cc-obj-temp-path cc-obj-temp-length @ + cc-obj-ti @ + c!
    [lit] 1 cc-obj-ti +!
  repeat,
  [lit] 5 cc-obj-temp-length +!
  [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 39 syscall6 cc-obj-pid !
  [lit] 16 cc-obj-ti !
  begin, cc-obj-ti @ while,
    [lit] 1 cc-obj-ti -!
    cc-obj-hex-digits cc-obj-pid @ [lit] 15 and + c@
    cc-obj-temp-path cc-obj-temp-length @ + cc-obj-ti @ + c!
    cc-obj-pid @ [lit] 16 / cc-obj-pid !
  repeat,
  [lit] 0 cc-obj-temp-path cc-obj-temp-length @ + [lit] 16 + c! ;
: cc-obj-abandon-output ( -- )
  cc-obj-fd @ 0< 0= if, cc-obj-fd @ close drop true cc-obj-fd ! then,
  cc-obj-temp-owned @ if,
    cc-obj-temp-path [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 87 syscall6 drop
    [lit] 0 cc-obj-temp-owned !
  then,
  [lit] 248 cc-die ;
: cc-obj-write ( nul-terminated-path -- )
  cc-obj-require-init cc-obj-reset-write cc-obj-path ! cc-obj-build
  cc-obj-make-temp-path cc-obj-check-output
  \ O_WRONLY | O_CREAT | O_EXCL; an existing temporary is never ours to unlink.
  cc-obj-temp-path [lit] 193 [lit] 420 open
  dup 0< if, [lit] 248 cc-die then, cc-obj-fd !
  true cc-obj-temp-owned !
  begin, cc-obj-written @ cc-out-pos @ < while,
    cc-obj-fd @ cc-out-buf cc-obj-written @ + cc-out-pos @ cc-obj-written @ - write
    dup [lit] 0 [lit] 4 - = if, drop
    else,
      dup [lit] 0 <= if, cc-obj-abandon-output then,
      cc-obj-written +!
    then,
  repeat,
  \ Linux may release the descriptor even when close reports an error.
  cc-obj-fd @ close true cc-obj-fd ! 0= 0= if, cc-obj-abandon-output then,
  cc-obj-temp-path cc-obj-path @ [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 82 syscall6
  0= 0= if, cc-obj-abandon-output then,
  cc-obj-reset-write ;
