# 37. Linking separate AMD64 objects

The direct route needs a linker that starts from independently emitted objects.
This chapter implements that boundary in Forth, above the library, arena and
I/O layers. Its input follows the ten-section relocatable-object contract of
Chapter 36. The linker does not invoke an assembler or a host linker.

The public interface loads object paths, selects an entry symbol, and writes a
static executable. Object bytes and the output use separately allocated memory;
input ranges must be validated before addresses are dereferenced.

## Canonical source

```forth file=140-cc-link.fth
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
: lnk-read-object ( path -- address size )
  [lit] 0 [lit] 0 open dup 0< if, [lit] 255 cc-die then,
  lnk-fd !
  lnk-fd @ [lit] 0 [lit] 2 [lit] 0 [lit] 0 [lit] 0 [lit] 8 syscall6
  dup [lit] 64 < if, [lit] 250 cc-die then,
  dup lnk-cap lnk-size !
  lnk-fd @ [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 8 syscall6
  0= 0= if, [lit] 255 cc-die then,
  lnk-size @ lnk-map lnk-op @ !
  [lit] 0 lnk-done !
  begin, lnk-done @ lnk-size @ < while,
    lnk-fd @ lnk-op @ @ lnk-done @ + lnk-size @ lnk-done @ - read
    dup [lit] 0 > 0= if, [lit] 255 cc-die then,
    lnk-done +!
  repeat,
  lnk-fd @ close 0= 0= if, [lit] 255 cc-die then,
  lnk-op @ @ lnk-size @ ;

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

: lnk-init
  [lit] 1 cc-src-line !
  [lit] 0 lnk-count ! [lit] 0 lnk-global-count !
  [lit] 0 lnk-entry-name ! [lit] 0 lnk-entry-len !
  lnk-hash-cap [lit] 32 * lnk-map lnk-globals ! ;
: lnk-entry  lnk-entry-len ! lnk-entry-name ! ;
```
