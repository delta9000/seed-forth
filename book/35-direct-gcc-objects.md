# Chapter 35 — Forth-written relocatable objects

## Goal and source coverage

This chapter adds an isolated object writer in `081-cc-object.fth`.
It turns section bytes, named symbols, and explicit relocations into an
ELF64 little-endian AMD64 `ET_REL` file. It does not compile C, resolve
external names, or produce a complete GCC bootstrap. Those are separate
steps. This is newly reconstructed source, not a recovered historical
implementation.

Concepts carried in: the library and syscall words of Chapters 1–12,
and the bounded output buffer and diagnostics of Chapter 21. Chapter 34
separated LP64 storage from calling convention; this chapter separates
machine-code emission from final address assignment.

Concepts introduced: section-relative values, stable symbol handles,
local-first ELF symbol numbering, explicit-addend relocation records,
and the distinction between file-backed storage and zero-filled memory.
Deferred: a C object-output driver, relocation resolution, archives,
COMDAT, TLS, exception unwinding, and the full GCC translation-unit size.

## 1. The interface between compiler and linker

Call `cc-obj-init` before beginning each object. Select one of
`cc-obj-text`, `cc-obj-rodata`, `cc-obj-data`, or `cc-obj-bss` with
`cc-obj-use`. `cc-obj-here` returns the current section offset.
`cc-obj-byte`, `cc-obj-4le`, `cc-obj-8le`, and `cc-obj-bytes (a n --)`
emit file bytes. `cc-obj-reserve (n -- offset)` reserves zeroed bytes,
including memory-only bytes in `.bss`. `cc-obj-align (n --)` accepts
powers of two through 4096, pads the section, and raises its alignment.

`cc-obj-symbol (name length binding type visibility section value size
-- id)` copies the name and returns a stable handle. Binding is local,
global, or weak; type is notype, object, func, or section; visibility is
default, internal, hidden, or protected. Each name has the `cc-obj-`
prefix. Sections are the four constants above, `cc-obj-undef`, or
`cc-obj-abs`. Undefined declarations have zero value and size.
`cc-obj-define (id section value size --)` finishes a forward declaration.
An undefined local is rejected when building. A section symbol must be
local, unnamed, have zero value/size, and refer to a real section.

`cc-obj-reloc (section offset kind id addend --)` records a relocation
against a stable handle, targeting `.text` or `.data`. Supported kinds
are `cc-obj-r64`, `cc-obj-pc32`, `cc-obj-plt32`, `cc-obj-r32`, and
`cc-obj-r32s`. Their ELF numbers are 1, 2, 4, 10, and 11. A call's rel32
field uses addend -4: ELF's place is the field's address while x86's
relative call counts from the instruction following the field.
`cc-obj-patch-4le/8le (value section offset --)` patch local fixups only
within bytes that already exist.

`cc-obj-build` serializes into `cc-out-buf` and `cc-out-pos`; calling it
again is deterministic. `cc-obj-write (NUL-path --)` builds and writes
with mode 0644, retries interrupted writes, and handles short writes.
The API is sequential and uses fixed scratch cells; it is not reentrant.

## 2. Ten sections, no assumed load address

The section-table order is null, `.text`, `.rodata`, `.data`, `.bss`,
`.rela.text`, `.rela.data`, `.symtab`, `.strtab`, `.shstrtab`. Thus text,
rodata, data, and bss have indexes 1–4; symbols have index 7; symbol names
have index 8; and section names have index 9. Both relocation sections
link to 7 and identify their target through `sh_info` (1 or 3).

Text has flags AX, rodata A, and data/bss WA. Bss has type `SHT_NOBITS`;
its length describes memory and never appears as payload bytes. All
section addresses are zero because only the linker knows final addresses.
The ELF header has no entry point or program headers. Every RELA and
symbol record is 24 bytes. Symbol-table `sh_info` identifies its first
nonlocal symbol; `sh_link` points to the string table.

The file begins with its ELF header, then text/rodata/data, symbols,
text/data relocations, both string tables, and the section headers.
Each payload begins at its declared alignment. Section-table order does
not constrain file payload order. Symbols come before relocations so the
writer can first assign final indexes, preserving insertion order within
locals and within globals/weak symbols. The mandatory all-zero symbol
occupies index zero. This explicit remapping prevents a late local symbol
from silently redirecting an already-recorded relocation.

## 3. Bounds and failures

The first writer allows 128 KiB for each backed section, 1 GiB for bss,
2048 symbols, 4096 relocations, and 64 KiB of symbol names. These are
initial bring-up limits, not a claim that GCC's generated translation
units fit. A later larger profile must coordinate section storage,
metadata storage, and the shared output buffer's capacity.

Every public size is checked for a negative/high-bit value before signed
comparison; growth checks use remaining capacity to avoid wrapping an
addition. Symbol extents must fit their section. Relocation and patch
fields must fit completely, including their four- or eight-byte width.
Reset discards counts, lengths, and alignments; newly reserved bytes are
zeroed so old content cannot leak into a later object.

Error 244 means use before initialization, invalid section, alignment,
or patch range; 245 means a
capacity limit; 246 means invalid symbol metadata; 247 means unsupported
or out-of-range relocation; 248 means file I/O failure. The existing
output emitter retains error 21 for output capacity. A failure exits
through `cc-die`; there is no partial-success return value.

## 4. Sources and evidence

The wire layout is derived from the [System V generic ABI, ELF sections,
symbols, and relocations](https://www.sco.com/developers/devspecs/gabi41.pdf)
and the [AMD64 psABI object-file specification](https://gitlab.com/x86-psABIs/x86-64-ABI/-/blob/master/x86-64-ABI/object-files.tex).
The implementation is original Forth reconstruction using this
repository's existing byte writers and syscall interface. No assembler,
linker, or C compiler runs inside the writer.

The fixture `tests/gcc/object-writer-fixture.fth` spells out x86 bytes
for two translation units. One calls `triple(7)` in the other and adds
its `shared_value` of 21. The caller also contains data relocations,
including a negative addend and a local symbol inserted after globals.
An independently linked executable must exit 42. Host inspection/linking
is a test oracle only; it is not a production route from Forth to GCC.

## Canonical source

```forth file=081-cc-object.fth
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

[lit] 131072 constant cc-obj-section-cap
[lit] 1073741824 constant cc-obj-bss-cap
[lit] 2048 constant cc-obj-symbol-cap
[lit] 4096 constant cc-obj-reloc-cap
[lit] 65536 constant cc-obj-string-cap
create cc-obj-payload  cc-obj-section-cap [lit] 3 * allot
create cc-obj-symbols  cc-obj-symbol-cap 1+ [lit] 64 * allot
create cc-obj-relocs  cc-obj-reloc-cap [lit] 40 * allot
create cc-obj-strings  cc-obj-string-cap allot
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

: cc-obj-sh ( section -- a )  [lit] 72 * cc-obj-sections + ;
: cc-obj-sym ( id -- a )  [lit] 64 * cc-obj-symbols + ;
: cc-obj-rel ( index -- a )  [lit] 40 * cc-obj-relocs + ;
: cc-obj-base ( section -- a )  1- cc-obj-section-cap * cc-obj-payload + ;
: cc-obj-length ( section -- n )  cc-obj-sh [lit] 32 + @ ;
: cc-obj-zero ( a n -- )
  begin, dup while,
    over [lit] 0 swap c! swap 1+ swap 1-
  repeat, 2drop ;

\ Reject high-bit values explicitly: the library's comparisons are signed.
: cc-obj-bound ( n maximum code -- )
  >r over 0< if, r@ cc-die then,
  > if, r@ cc-die then, r> drop ;
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
  else, cc-obj-section-cap then,
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

variable cc-obj-fd
variable cc-obj-written
: cc-obj-write ( nul-terminated-path -- )
  cc-obj-build [lit] 577 [lit] 420 open
  dup 0< if, [lit] 248 cc-die then, cc-obj-fd !
  [lit] 0 cc-obj-written !
  begin, cc-obj-written @ cc-out-pos @ < while,
    cc-obj-fd @ cc-out-buf cc-obj-written @ + cc-out-pos @ cc-obj-written @ - write
    dup [lit] 0 [lit] 4 - = if, drop
    else,
      dup [lit] 0 <= if, cc-obj-fd @ close drop [lit] 248 cc-die then,
      cc-obj-written +!
    then,
  repeat,
  cc-obj-fd @ close 0< if, [lit] 248 cc-die then, ;
```

## Try it

From the repository root, build the seed and run the focused writer
check. The host tools used by the check are independent test oracles.

```sh
./build.sh
python3 tests/gcc/object-writer-check.py
```

## Exercises

1. **★** Explain why `.bss` can have a nonzero size and no file payload.
2. **★★** Insert another local symbol after the caller's declarations;
   inspect the changed ELF indexes and show that its call target survives.
3. **★★** Change a PC-relative relocation's addend from -4 to zero and
   predict the address before running the linked executable.
4. **★★★** Design an output-capacity extension that preserves the same
   public handles while supporting a large GCC-generated translation unit.

## Takeaways

- Section offsets let machine-code generation finish before final addresses exist.
- Stable handles and local-first remapping preserve relocation targets across ELF symbol ordering.
- Explicit bounds and independent host inspection make the first object writer reviewable without claiming a complete compiler bootstrap.

Next: the scalar System V compiler profile and the Forth object linker
consume this boundary to establish a direct path between translation units.
