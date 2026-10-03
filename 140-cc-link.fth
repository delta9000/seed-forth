\ 140-cc-link.fth -- bounded static AMD64 ELF linker, written in Forth.
\ Load after 010-lib.fth, 020-cc-arena.fth, and 030-cc-io.fth.
\ The input is 081's ten-section ELF64 ET_REL contract; no host linker.
\ API: lnk-init, lnk-add-object ( NUL-path -- ),
\      lnk-entry ( name length -- ), lnk-link ( NUL-output-path -- ).
\ Errors: 250 metadata, 251 capacity, 252 duplicate strong definition,
\ 253 unresolved symbol/entry, 254 relocation/range, 255 file I/O.

[lit] 256 constant lnk-object-cap
[lit] 65536 constant lnk-symbol-cap
[lit] 65536 constant lnk-global-cap
[lit] 131072 constant lnk-hash-cap
[lit] 268435456 constant lnk-byte-cap
[lit] 1048576 constant lnk-align-cap
[lit] 4194304 constant lnk-base
[lit] 128 constant lnk-object-size
create lnk-objects  lnk-object-cap lnk-object-size * allot
variable lnk-count
variable lnk-globals
variable lnk-global-count
variable lnk-entry-name
variable lnk-entry-len
variable lnk-image
variable lnk-file-size
variable lnk-memory-size
variable lnk-rx-size
variable lnk-rw-start
variable lnk-entry-value
variable lnk-op
variable lnk-si
variable lnk-oi
variable lnk-sp
variable lnk-np
variable lnk-nl

\ Track source identities independently of selected archive members.
[lit] 1024 constant lnk-input-cap
create lnk-inputs lnk-input-cap [lit] 16 * allot
variable lnk-input-count
: lnk-note-input ( device inode -- )
  lnk-input-count @ 1+ lnk-input-cap [lit] 251 cc-check-cap
  lnk-input-count @ [lit] 16 * lnk-inputs + >r
  r@ [lit] 8 + ! r> ! [lit] 1 lnk-input-count +! ;

: lnk-bad  [lit] 250 cc-die ;
: lnk-need  0= if, lnk-bad then, ;
: lnk-cap  lnk-byte-cap [lit] 251 cc-check-cap ;
: lnk-nonnegative  dup 0< if, lnk-bad then, ;
: lnk-u16  dup c@ swap 1+ c@ [lit] 256 * + ;
: lnk-u32
  dup lnk-u16 swap [lit] 2 + lnk-u16 [lit] 65536 * + ;
: lnk-w16  >r dup r@ c! [lit] 256 / r> 1+ c! ;
: lnk-w32
  >r dup r@ lnk-w16 [lit] 65536 / r> [lit] 2 + lnk-w16 ;
: lnk-map
  dup 0= if, drop [lit] 1 then,
  [lit] 0 swap [lit] 3 [lit] 34 true [lit] 0 [lit] 9 syscall6
  dup 0< if, [lit] 251 cc-die then, ;
: lnk-object  lnk-object-size * lnk-objects + ;
: lnk-field  lnk-op @ + ;
: lnk-section  [lit] 64 * [lit] 16 lnk-field @ + ;
: lnk-place  [lit] 8 * [lit] 56 + lnk-field ;
: lnk-symbol  [lit] 24 * [lit] 24 lnk-field @ + ;
: lnk-binding  [lit] 4 + c@ [lit] 16 / ;
: lnk-shndx  [lit] 6 + lnk-u16 ;

\ All offsets are checked by subtraction, before pointer arithmetic.
: lnk-span ( offset size -- address )
  lnk-nonnegative >r lnk-nonnegative
  dup [lit] 8 lnk-field @ <= lnk-need
  [lit] 8 lnk-field @ over - r> >= lnk-need
  lnk-op @ @ + ;
: lnk-alignment ( alignment -- alignment )
  dup [lit] 0 > lnk-need
  dup lnk-align-cap <= lnk-need
  dup dup 1- and 0= lnk-need ;
: lnk-align ( offset alignment -- aligned )
  1- dup >r + r> dup nand and ;
: lnk-copy ( source destination size -- )
  begin, dup while,
    >r over c@ over c! 1+ swap 1+ swap r> 1-
  repeat, drop 2drop ;

variable lnk-fd
variable lnk-size
variable lnk-done
variable lnk-path
create lnk-stat-buffer  [lit] 144 allot
: lnk-fstat ( fd -- )
  lnk-stat-buffer [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 5 syscall6
  0= 0= if, [lit] 255 cc-die then, ;
: lnk-read-file ( path -- address size )
  dup [lit] 120 lnk-field !
  [lit] 0 [lit] 0 open dup 0< if, [lit] 255 cc-die then,
  lnk-fd !
  lnk-fd @ [lit] 0 [lit] 2 [lit] 0 [lit] 0 [lit] 0 [lit] 8 syscall6
  dup 0< if, [lit] 255 cc-die then,
  dup lnk-cap lnk-size !
  lnk-fd @ [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 8 syscall6
  0= 0= if, [lit] 255 cc-die then,
  lnk-size @ lnk-map lnk-op @ !
  [lit] 0 lnk-done !
  begin, lnk-done @ lnk-size @ < while,
    lnk-fd @ lnk-op @ @ lnk-done @ + lnk-size @ lnk-done @ - read
    dup [lit] 0 [lit] 4 - = if, drop
    else,
      dup [lit] 0 > 0= if, [lit] 255 cc-die then,
      lnk-done +!
    then,
  repeat,
  lnk-fd @ lnk-fstat
  lnk-stat-buffer @ [lit] 104 lnk-field !
  lnk-stat-buffer [lit] 8 + @ [lit] 112 lnk-field !
  lnk-stat-buffer @ lnk-stat-buffer [lit] 8 + @ lnk-note-input
  lnk-fd @ close 0= 0= if, [lit] 255 cc-die then,
  lnk-op @ @ lnk-size @ ;
: lnk-read-object ( path -- address size )
  lnk-read-file dup [lit] 64 < if, [lit] 250 cc-die then, ;

\ Find a terminating NUL strictly inside a previously validated string table.
variable lnk-string-end
variable lnk-string-base
variable lnk-string-size
: lnk-string ( index base size -- address length )
  lnk-string-size ! lnk-string-base !
  lnk-nonnegative dup lnk-string-size @ < lnk-need
  lnk-string-base @ + [lit] 0
  lnk-string-base @ lnk-string-size @ + lnk-string-end !
  begin,
    2dup + lnk-string-end @ < lnk-need
    2dup + c@
  while, 1+ repeat, ;

: lnk-symbol-name ( symbol -- address length )
  lnk-u32 [lit] 40 lnk-field @ [lit] 48 lnk-field @ lnk-string ;

: lnk-unmap ( address length -- )
  [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 11 syscall6
  0= 0= if, [lit] 251 cc-die then, ;
: lnk-release
  [lit] 0 lnk-oi !
  begin, lnk-oi @ lnk-count @ < while,
    lnk-oi @ lnk-object dup @ swap [lit] 8 + @ lnk-unmap
    [lit] 1 lnk-oi +!
  repeat,
  lnk-globals @ if,
    lnk-globals @ lnk-hash-cap [lit] 32 * lnk-unmap
  then,
  lnk-image @ if, lnk-image @ lnk-file-size @ lnk-unmap then,
  [lit] 0 lnk-count ! [lit] 0 lnk-globals ! [lit] 0 lnk-image ! ;
: lnk-init
  lnk-release
  [lit] 1 cc-src-line !
  [lit] 0 lnk-count ! [lit] 0 lnk-global-count ! [lit] 0 lnk-input-count !
  [lit] 0 lnk-entry-name ! [lit] 0 lnk-entry-len !
  lnk-hash-cap [lit] 32 * lnk-map lnk-globals ! ;
: lnk-entry  lnk-entry-len ! lnk-entry-name ! ;

\ Ten section roles are fixed by the object-writer boundary.
create lnk-section-types
  [lit] 0 , [lit] 1 , [lit] 1 , [lit] 1 , [lit] 8 ,
  [lit] 4 , [lit] 4 , [lit] 2 , [lit] 3 , [lit] 3 ,
create lnk-section-flags
  [lit] 0 , [lit] 6 , [lit] 2 , [lit] 3 , [lit] 3 ,
  [lit] 0 , [lit] 0 , [lit] 0 , [lit] 0 , [lit] 0 ,
variable lnk-sh
variable lnk-shstr
variable lnk-shstrlen
: lnk-zero? ( address length -- flag )
  begin, dup while,
    over c@ if, 2drop [lit] 0 exit, then,
    1- swap 1+ swap
  repeat, 2drop true ;
: lnk-multiple24 ( size -- count )
  lnk-nonnegative dup [lit] 24 / dup >r [lit] 24 * = lnk-need r> ;
: lnk-header
  lnk-op @ @ lnk-sh !
  lnk-sh @ lnk-u32 [lit] 1179403647 = lnk-need
  lnk-sh @ [lit] 4 + c@ [lit] 2 = lnk-need
  lnk-sh @ [lit] 5 + c@ [lit] 1 = lnk-need
  lnk-sh @ [lit] 6 + c@ [lit] 1 = lnk-need
  lnk-sh @ [lit] 7 + c@ dup 0= swap [lit] 3 = or lnk-need
  lnk-sh @ [lit] 8 + [lit] 8 lnk-zero? lnk-need
  lnk-sh @ [lit] 16 + lnk-u16 [lit] 1 = lnk-need
  lnk-sh @ [lit] 18 + lnk-u16 [lit] 62 = lnk-need
  lnk-sh @ [lit] 20 + lnk-u32 [lit] 1 = lnk-need
  lnk-sh @ [lit] 24 + @ 0= lnk-need
  lnk-sh @ [lit] 32 + @ 0= lnk-need
  lnk-sh @ [lit] 48 + lnk-u32 0= lnk-need
  lnk-sh @ [lit] 52 + lnk-u16 [lit] 64 = lnk-need
  lnk-sh @ [lit] 54 + lnk-u16 0= lnk-need
  lnk-sh @ [lit] 56 + lnk-u16 0= lnk-need
  lnk-sh @ [lit] 58 + lnk-u16 [lit] 64 = lnk-need
  lnk-sh @ [lit] 60 + lnk-u16 [lit] 10 = lnk-need
  lnk-sh @ [lit] 62 + lnk-u16 [lit] 9 = lnk-need
  lnk-sh @ [lit] 40 + @ [lit] 640 lnk-span [lit] 16 lnk-field !
  [lit] 0 lnk-section [lit] 64 lnk-zero? lnk-need ;
: lnk-sections
  [lit] 1 lnk-si !
  begin, lnk-si @ [lit] 10 < while,
    lnk-si @ lnk-section lnk-sh !
    lnk-sh @ [lit] 4 + lnk-u32
    lnk-si @ lnk-section-types cell[] @ = lnk-need
    lnk-sh @ [lit] 8 + @
    lnk-si @ lnk-section-flags cell[] @ = lnk-need
    lnk-sh @ [lit] 16 + @ 0= lnk-need
    lnk-sh @ [lit] 32 + @ lnk-nonnegative dup lnk-cap drop
    lnk-si @ [lit] 4 <> if,
      lnk-sh @ [lit] 24 + @ lnk-sh @ [lit] 32 + @ lnk-span drop
    then,
    lnk-sh @ [lit] 48 + @ lnk-alignment drop
    lnk-si @ [lit] 5 < if,
      lnk-sh @ [lit] 40 + lnk-u32 0= lnk-need
      lnk-sh @ [lit] 44 + lnk-u32 0= lnk-need
      lnk-sh @ [lit] 56 + @ 0= lnk-need
    else,
      lnk-si @ [lit] 8 < if,
        lnk-sh @ [lit] 48 + @ [lit] 8 = lnk-need
        lnk-sh @ [lit] 56 + @ [lit] 24 = lnk-need
        lnk-sh @ [lit] 32 + @ lnk-multiple24 drop
        lnk-si @ [lit] 7 < if,
          lnk-sh @ [lit] 40 + lnk-u32 [lit] 7 = lnk-need
          lnk-sh @ [lit] 44 + lnk-u32
          lnk-si @ [lit] 5 - [lit] 2 * 1+ = lnk-need
        else,
          lnk-sh @ [lit] 40 + lnk-u32 [lit] 8 = lnk-need
        then,
      else,
        lnk-sh @ [lit] 40 + lnk-u32 0= lnk-need
        lnk-sh @ [lit] 44 + lnk-u32 0= lnk-need
        lnk-sh @ [lit] 56 + @ 0= lnk-need
        lnk-sh @ [lit] 48 + @ [lit] 1 = lnk-need
      then,
    then,
    [lit] 1 lnk-si +!
  repeat,
  [lit] 7 lnk-section lnk-sh !
  lnk-sh @ [lit] 24 + @ lnk-op @ @ + [lit] 24 lnk-field !
  lnk-sh @ [lit] 32 + @ lnk-multiple24
  dup [lit] 0 > lnk-need
  dup lnk-symbol-cap [lit] 251 cc-check-cap [lit] 32 lnk-field !
  lnk-sh @ [lit] 44 + lnk-u32
  dup [lit] 0 > lnk-need
  dup [lit] 32 lnk-field @ <= lnk-need [lit] 56 lnk-field !
  [lit] 8 lnk-section lnk-sh !
  lnk-sh @ [lit] 24 + @ lnk-op @ @ + [lit] 40 lnk-field !
  lnk-sh @ [lit] 32 + @ dup [lit] 0 > lnk-need [lit] 48 lnk-field !
  [lit] 40 lnk-field @ c@ 0= lnk-need
  [lit] 9 lnk-section lnk-sh !
  lnk-sh @ [lit] 24 + @ lnk-op @ @ + lnk-shstr !
  lnk-sh @ [lit] 32 + @ dup [lit] 0 > lnk-need lnk-shstrlen !
  lnk-shstr @ c@ 0= lnk-need
  [lit] 0 lnk-si !
  begin, lnk-si @ [lit] 10 < while,
    lnk-si @ lnk-section lnk-u32 lnk-shstr @ lnk-shstrlen @ lnk-string 2drop
    [lit] 1 lnk-si +!
  repeat,
  [lit] 0 lnk-symbol [lit] 24 lnk-zero? lnk-need ;

\ Global names use open addressing, at most half full. Each slot stores
\ name pointer, name length, the chosen symbol, and its owning object.
variable lnk-hname
variable lnk-hlen
variable lnk-hash
variable lnk-hi
variable lnk-hslot
: lnk-find ( name length -- slot )
  lnk-hlen ! lnk-hname ! [lit] 5381 lnk-hash ! [lit] 0 lnk-hi !
  begin, lnk-hi @ lnk-hlen @ < while,
    lnk-hash @ [lit] 33 * lnk-hname @ lnk-hi @ + c@ +
    [lit] 2147483647 and lnk-hash ! [lit] 1 lnk-hi +!
  repeat,
  begin,
    lnk-hash @ lnk-hash-cap 1- and dup lnk-hash !
    [lit] 32 * lnk-globals @ + lnk-hslot !
    lnk-hslot @ @ 0= if, lnk-hslot @ exit, then,
    lnk-hslot @ [lit] 8 + @ lnk-hlen @ = if,
      lnk-hslot @ @ lnk-hname @ lnk-hlen @ bytes-eq if,
        lnk-hslot @ exit,
      then,
    then,
    [lit] 1 lnk-hash +!
  again, ;
variable lnk-slot
variable lnk-old
: lnk-choose
  lnk-sp @ lnk-slot @ [lit] 16 + !
  lnk-op @ lnk-slot @ [lit] 24 + ! ;
: lnk-register
  lnk-sp @ lnk-symbol-name
  dup [lit] 0 > lnk-need lnk-find lnk-slot !
  lnk-slot @ @ 0= if,
    lnk-global-count @ 1+ lnk-global-cap [lit] 251 cc-check-cap
    [lit] 1 lnk-global-count +!
    lnk-hname @ lnk-slot @ ! lnk-hlen @ lnk-slot @ [lit] 8 + !
    lnk-choose exit,
  then,
  lnk-slot @ [lit] 16 + @ lnk-old !
  lnk-sp @ lnk-shndx 0= if,
    lnk-old @ lnk-shndx 0=
    lnk-old @ lnk-binding [lit] 2 = and
    lnk-sp @ lnk-binding [lit] 1 = and if, lnk-choose then,
    exit,
  then,
  lnk-old @ lnk-shndx 0= if, lnk-choose exit, then,
  lnk-sp @ lnk-binding [lit] 2 = if, exit, then,
  lnk-old @ lnk-binding [lit] 2 = if, lnk-choose exit, then,
  [lit] 252 cc-die ;
variable lnk-symbol-index
variable lnk-index
variable lnk-value
variable lnk-length
: lnk-validate-symbol
  lnk-sp @ lnk-symbol-name 2drop
  lnk-sp @ lnk-binding dup [lit] 2 <= lnk-need
  lnk-symbol-index @ [lit] 56 lnk-field @ < if,
    0= lnk-need
  else,
    [lit] 0 > lnk-need
  then,
  lnk-sp @ [lit] 4 + c@ [lit] 15 and [lit] 4 <= lnk-need
  lnk-sp @ [lit] 5 + c@ [lit] 3 <= lnk-need
  lnk-sp @ lnk-shndx lnk-index !
  lnk-index @ 0= if,
    lnk-sp @ [lit] 8 + @ 0= lnk-need
    lnk-sp @ [lit] 16 + @ 0= lnk-need
    lnk-symbol-index @ 0= 0= if,
      lnk-sp @ lnk-binding [lit] 0 > lnk-need
    then,
  else,
    lnk-index @ [lit] 65521 <> if,
      lnk-index @ [lit] 4 <= lnk-need
      lnk-sp @ [lit] 8 + @ lnk-nonnegative lnk-value !
      lnk-sp @ [lit] 16 + @ lnk-nonnegative lnk-length !
      lnk-index @ lnk-section [lit] 32 + @
      dup lnk-value @ >= lnk-need
      lnk-value @ - lnk-length @ >= lnk-need
    then,
  then,
  ;
: lnk-check-symbol
  lnk-validate-symbol lnk-sp @ lnk-binding if, lnk-register then, ;
: lnk-accept-object
  lnk-header lnk-sections
  [lit] 0 lnk-symbol-index !
  begin, lnk-symbol-index @ [lit] 32 lnk-field @ < while,
    lnk-symbol-index @ lnk-symbol lnk-sp ! lnk-check-symbol
    [lit] 1 lnk-symbol-index +!
  repeat,
  [lit] 1 lnk-count +! ;
: lnk-add-object
  lnk-count @ 1+ lnk-object-cap [lit] 251 cc-check-cap
  lnk-count @ lnk-object lnk-op !
  lnk-read-object [lit] 8 lnk-field ! drop lnk-accept-object ;
\ Archive members are copied: ordinary object release owns every mapping.
variable lnk-buffer-a
variable lnk-buffer-n
: lnk-add-buffer ( address size -- )
  lnk-buffer-n ! lnk-buffer-a !
  lnk-buffer-n @ [lit] 64 >= lnk-need
  lnk-count @ 1+ lnk-object-cap [lit] 251 cc-check-cap
  lnk-count @ lnk-object lnk-op !
  lnk-buffer-n @ lnk-map lnk-op @ !
  lnk-buffer-n @ [lit] 8 lnk-field !
  lnk-buffer-a @ lnk-op @ @ lnk-buffer-n @ lnk-copy
  lnk-accept-object ;

\ Place sections in four passes. Text and rodata share an RX mapping;
\ data and BSS share an RW mapping. BSS consumes no bytes in the file.
variable lnk-cursor
: lnk-layout-section
  [lit] 0 lnk-oi !
  begin, lnk-oi @ lnk-count @ < while,
    lnk-oi @ lnk-object lnk-op !
    lnk-si @ lnk-section lnk-sh !
    lnk-cursor @ lnk-sh @ [lit] 48 + @ lnk-align
    dup lnk-cap dup lnk-si @ lnk-place !
    lnk-sh @ [lit] 32 + @ + dup lnk-cap lnk-cursor !
    [lit] 1 lnk-oi +!
  repeat, ;
: lnk-layout
  lnk-count @ [lit] 0 > lnk-need
  [lit] 4096 lnk-cursor !
  [lit] 1 lnk-si ! lnk-layout-section
  [lit] 2 lnk-si ! lnk-layout-section
  lnk-cursor @ lnk-rx-size !
  lnk-cursor @ [lit] 4096 lnk-align dup lnk-cap
  dup lnk-rw-start ! lnk-cursor !
  [lit] 3 lnk-si ! lnk-layout-section
  lnk-cursor @ lnk-file-size !
  [lit] 4 lnk-si ! lnk-layout-section
  lnk-cursor @ lnk-memory-size !
  lnk-file-size @ lnk-map lnk-image ! ;
: lnk-copy-sections
  [lit] 0 lnk-oi !
  begin, lnk-oi @ lnk-count @ < while,
    lnk-oi @ lnk-object lnk-op ! [lit] 1 lnk-si !
    begin, lnk-si @ [lit] 4 < while,
      lnk-si @ lnk-section lnk-sh !
      lnk-sh @ [lit] 24 + @ lnk-op @ @ +
      lnk-si @ lnk-place @ lnk-image @ +
      lnk-sh @ [lit] 32 + @ lnk-copy
      [lit] 1 lnk-si +!
    repeat,
    [lit] 1 lnk-oi +!
  repeat, ;
: lnk-defined-value ( symbol -- value )
  dup lnk-shndx 0= if, drop [lit] 0 exit, then,
  dup lnk-shndx [lit] 65521 = if, [lit] 8 + @ exit, then,
  dup [lit] 8 + @ swap lnk-shndx lnk-place @ + lnk-base + ;
variable lnk-reference
variable lnk-selected
variable lnk-resolved-slot
: lnk-resolve ( symbol -- value )
  dup lnk-binding 0= if, lnk-defined-value exit, then,
  dup lnk-reference ! lnk-symbol-name lnk-find lnk-resolved-slot !
  lnk-resolved-slot @ @ 0= if, [lit] 253 cc-die then,
  lnk-resolved-slot @ [lit] 16 + @ lnk-selected !
  lnk-selected @ lnk-shndx 0= if,
    lnk-reference @ lnk-binding [lit] 2 <> if, [lit] 253 cc-die then,
    [lit] 0 exit,
  then,
  lnk-op @ >r lnk-resolved-slot @ [lit] 24 + @ lnk-op !
  lnk-selected @ lnk-defined-value r> lnk-op ! ;
: lnk-check-unresolved
  [lit] 0 lnk-oi !
  begin, lnk-oi @ lnk-count @ < while,
    lnk-oi @ lnk-object lnk-op ! [lit] 1 lnk-symbol-index !
    begin, lnk-symbol-index @ [lit] 32 lnk-field @ < while,
      lnk-symbol-index @ lnk-symbol dup lnk-binding if,
        lnk-resolve drop
      else, drop then,
      [lit] 1 lnk-symbol-index +!
    repeat,
    [lit] 1 lnk-oi +!
  repeat, ;
: lnk-find-entry
  lnk-entry-len @ [lit] 0 > 0= if, [lit] 253 cc-die then,
  lnk-entry-name @ lnk-entry-len @ lnk-find lnk-slot !
  lnk-slot @ @ 0= if, [lit] 253 cc-die then,
  lnk-slot @ [lit] 16 + @ lnk-sp !
  lnk-sp @ lnk-shndx [lit] 1 <> if, [lit] 253 cc-die then,
  lnk-slot @ [lit] 24 + @ lnk-op !
  lnk-sp @ [lit] 8 + @ [lit] 1 lnk-section [lit] 32 + @
  < 0= if, [lit] 253 cc-die then,
  lnk-sp @ lnk-defined-value lnk-entry-value ! ;

\ RELA's addend is a signed 64-bit cell. Arithmetic is modulo 2^64;
\ 32-bit relocations then explicitly check zero or sign extension.
variable lnk-rp
variable lnk-rend
variable lnk-rtype
variable lnk-roff
variable lnk-rwidth
variable lnk-target
variable lnk-patch
variable lnk-rvalue
: lnk-reloc-fail  [lit] 254 cc-die ;
: lnk-signed32? ( value -- flag )
  dup [lit] 4294967295 and
  dup [lit] 2147483648 and if,
    [lit] 0 [lit] 4294967296 - or
  then, = ;
: lnk-relocation
  lnk-rp @ [lit] 8 + lnk-u32 lnk-rtype !
  lnk-rtype @ [lit] 1 = if,
    [lit] 8 lnk-rwidth !
  else,
    lnk-rtype @ [lit] 2 = lnk-rtype @ [lit] 4 = or
    lnk-rtype @ [lit] 10 = or lnk-rtype @ [lit] 11 = or
    0= if, lnk-reloc-fail then,
    [lit] 4 lnk-rwidth !
  then,
  lnk-rp @ @ dup 0< if, lnk-reloc-fail then, lnk-roff !
  lnk-target @ lnk-section [lit] 32 + @
  dup lnk-roff @ < if, lnk-reloc-fail then,
  lnk-roff @ - lnk-rwidth @ < if, lnk-reloc-fail then,
  lnk-rp @ [lit] 12 + lnk-u32
  dup [lit] 32 lnk-field @ >= if, lnk-reloc-fail then,
  lnk-symbol lnk-resolve lnk-rp @ [lit] 16 + @ + lnk-rvalue !
  lnk-target @ lnk-place @ lnk-roff @ + lnk-patch !
  lnk-rtype @ [lit] 2 = lnk-rtype @ [lit] 4 = or if,
    lnk-rvalue @ lnk-patch @ lnk-base + - lnk-rvalue !
  then,
  lnk-rtype @ [lit] 10 = if,
    lnk-rvalue @ [lit] 4294967296 / 0= 0=
    if, lnk-reloc-fail then,
  then,
  lnk-rtype @ [lit] 2 = lnk-rtype @ [lit] 4 = or
  lnk-rtype @ [lit] 11 = or if,
    lnk-rvalue @ lnk-signed32? 0= if, lnk-reloc-fail then,
  then,
  lnk-rvalue @ lnk-image @ lnk-patch @ +
  lnk-rwidth @ [lit] 8 = if, ! else, lnk-w32 then, ;
: lnk-relocate
  [lit] 0 lnk-oi !
  begin, lnk-oi @ lnk-count @ < while,
    lnk-oi @ lnk-object lnk-op ! [lit] 5 lnk-si !
    begin, lnk-si @ [lit] 7 < while,
      lnk-si @ lnk-section lnk-sh !
      lnk-sh @ [lit] 44 + lnk-u32 lnk-target !
      lnk-sh @ [lit] 24 + @ lnk-op @ @ + dup lnk-rp !
      lnk-sh @ [lit] 32 + @ + lnk-rend !
      begin, lnk-rp @ lnk-rend @ < while,
        lnk-relocation [lit] 24 lnk-rp +!
      repeat,
      [lit] 1 lnk-si +!
    repeat,
    [lit] 1 lnk-oi +!
  repeat, ;

\ The executable needs program headers only. No dynamic loader or runtime
\ section table participates in loading these two page-congruent segments.
variable lnk-ph
: lnk-output-header
  lnk-image @ lnk-sh !
  [lit] 1179403647 lnk-sh @ lnk-w32
  [lit] 2 lnk-sh @ [lit] 4 + c!
  [lit] 1 lnk-sh @ [lit] 5 + c!
  [lit] 1 lnk-sh @ [lit] 6 + c!
  [lit] 2 lnk-sh @ [lit] 16 + lnk-w16
  [lit] 62 lnk-sh @ [lit] 18 + lnk-w16
  [lit] 1 lnk-sh @ [lit] 20 + lnk-w32
  lnk-entry-value @ lnk-sh @ [lit] 24 + !
  [lit] 64 lnk-sh @ [lit] 32 + !
  [lit] 64 lnk-sh @ [lit] 52 + lnk-w16
  [lit] 56 lnk-sh @ [lit] 54 + lnk-w16
  [lit] 2 lnk-sh @ [lit] 56 + lnk-w16
  lnk-sh @ [lit] 64 + lnk-ph !
  [lit] 1 lnk-ph @ lnk-w32
  [lit] 5 lnk-ph @ [lit] 4 + lnk-w32
  lnk-base lnk-ph @ [lit] 16 + !
  lnk-base lnk-ph @ [lit] 24 + !
  lnk-rx-size @ lnk-ph @ [lit] 32 + !
  lnk-rx-size @ lnk-ph @ [lit] 40 + !
  [lit] 4096 lnk-ph @ [lit] 48 + !
  [lit] 56 lnk-ph +!
  [lit] 1 lnk-ph @ lnk-w32
  [lit] 6 lnk-ph @ [lit] 4 + lnk-w32
  lnk-rw-start @ lnk-ph @ [lit] 8 + !
  lnk-rw-start @ lnk-base + dup lnk-ph @ [lit] 16 + !
  lnk-ph @ [lit] 24 + !
  lnk-file-size @ lnk-rw-start @ - lnk-ph @ [lit] 32 + !
  lnk-memory-size @ lnk-rw-start @ - lnk-ph @ [lit] 40 + !
  [lit] 4096 lnk-ph @ [lit] 48 + ! ;
\ Complete validation precedes output creation. Refuse input aliases by
\ inode/device, then publish through an exclusive sibling temporary file.
create lnk-temp-path  [lit] 4096 allot
create lnk-temp-suffix  s, .lnk-
create lnk-hex-digits  s, 0123456789abcdef
variable lnk-temp-length
variable lnk-pid
variable lnk-ti
: lnk-check-output-alias
  lnk-path @ lnk-stat-buffer [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 4 syscall6
  dup [lit] 0 [lit] 2 - = if, drop exit, then,
  0= 0= if, [lit] 255 cc-die then,
  [lit] 0 lnk-oi !
  begin, lnk-oi @ lnk-input-count @ < while,
    lnk-oi @ [lit] 16 * lnk-inputs +
    dup @ lnk-stat-buffer @ =
    swap [lit] 8 + @ lnk-stat-buffer [lit] 8 + @ = and
    if, [lit] 255 cc-die then,
    [lit] 1 lnk-oi +!
  repeat, ;
: lnk-make-temp-path
  [lit] 0 lnk-temp-length !
  begin, lnk-path @ lnk-temp-length @ + c@ dup while,
    lnk-temp-length @ [lit] 4069 > if, [lit] 255 cc-die then,
    lnk-temp-path lnk-temp-length @ + c!
    [lit] 1 lnk-temp-length +!
  repeat, drop
  lnk-temp-suffix lnk-temp-path lnk-temp-length @ + [lit] 5 lnk-copy
  [lit] 5 lnk-temp-length +!
  [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 39 syscall6 lnk-pid !
  [lit] 16 lnk-ti !
  begin, lnk-ti @ while,
    [lit] 0 [lit] 1 - lnk-ti +!
    lnk-hex-digits lnk-pid @ [lit] 15 and + c@
    lnk-temp-path lnk-temp-length @ + lnk-ti @ + c!
    lnk-pid @ [lit] 16 / lnk-pid !
  repeat,
  [lit] 0 lnk-temp-path lnk-temp-length @ + [lit] 16 + c! ;
: lnk-abandon-output
  lnk-fd @ close drop
  lnk-temp-path [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 87 syscall6 drop
  [lit] 255 cc-die ;
: lnk-write
  lnk-check-output-alias lnk-make-temp-path
  lnk-temp-path [lit] 193 [lit] 493 open
  dup 0< if, [lit] 255 cc-die then, lnk-fd !
  [lit] 0 lnk-done !
  begin, lnk-done @ lnk-file-size @ < while,
    lnk-fd @ lnk-image @ lnk-done @ + lnk-file-size @ lnk-done @ - write
    dup [lit] 0 [lit] 4 - = if, drop
    else,
      dup [lit] 0 <= if, lnk-abandon-output then, lnk-done +!
    then,
  repeat,
  lnk-fd @ close 0= 0= if, lnk-abandon-output then,
  lnk-temp-path lnk-path @ [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 82 syscall6
  0= 0= if, lnk-abandon-output then, ;
: lnk-link
  lnk-path !
  lnk-image @ if,
    lnk-image @ lnk-file-size @ lnk-unmap [lit] 0 lnk-image !
  then,
  lnk-layout lnk-check-unresolved lnk-find-entry
  lnk-copy-sections lnk-relocate lnk-output-header lnk-write ;
