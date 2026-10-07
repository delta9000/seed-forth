\ tools/obj-asm.fth -- hand-encoded machine code to an ELF relocatable object.
\ Load after 010-lib.fth, 020-cc-arena.fth, 030-cc-io.fth and 081-cc-object.fth.
\
\ For the few objects that must be written in assembly (K1's entry, trap and
\ syscall paths: k1/k1-asm.fth).  It does not encode instructions: the input
\ is the bytes, in hex, with a GAS-like spelling for sections, labels and
\ references.  What it adds over 122-cc-sysv-runtime.fth's byte lists is
\ names: labels, forward references and relocations, so one object can be
\ written the way an assembler listing reads.  081 writes the object; the
\ Forth linker (140) or any other ELF linker links it.
\
\   cc-obj-init asm{ ... }asm  driver-output cc-obj-write
\
\ Tokens between asm{ and }asm (Forth's \ and ( comments still work):
\   .text .data          append to that section
\   .globl NAME          NAME is global (before or after its definition)
\   NAME:                define NAME at the current offset
\   48 89 e7  or 4889e7  bytes: pairs of hex digits
\   %NAME  %NAME+N       4-byte PC-relative to NAME+N (R_X86_64_PC32)
\   ^NAME                the same, as a call or jump (R_X86_64_PLT32)
\   !NAME                1-byte PC-relative; NAME must be in this section
\   *NAME  *NAME+N       8-byte absolute address (R_X86_64_64)
\ Like GAS, a PC-relative reference to a label defined in the same section
\ is resolved here (any binding) and leaves no relocation.  The relocation
\ addend of a 4-byte reference is N-4: the CPU adds the displacement to the
\ end of the field, so write %NAME-K when K immediate bytes follow it.
\ Every label becomes a symbol: local unless .globl, undefined ones global.
\
\ Errors print "obj-asm: " and the line, then exit with a status:
\ 1 a token is none of the above, 2 a label is defined twice, 3 a 1-byte
\ reference is out of range or not local, 4 a name is too long, 5 a table
\ is full, 6 end of input before }asm.

create oa-prefix s, obj-asm: bl c,
: oa-die ( status -- ) oa-prefix [lit] 9 cc-err-write cc-die ;

\ Labels: name (63 bytes max), length, section, offset, defined?, global?,
\ the symbol id 081 assigned (at }asm).
[lit] 256 constant oa-label-cap
[lit] 112 constant oa-label-size
create oa-labels oa-label-cap oa-label-size * allot
variable oa-label-count
: oa-label ( index -- a ) oa-label-size * oa-labels + ;
: oa-len ( a -- a' ) [lit] 64 + ;
: oa-sec ( a -- a' ) [lit] 72 + ;
: oa-off ( a -- a' ) [lit] 80 + ;
: oa-defined ( a -- a' ) [lit] 88 + ;
: oa-global ( a -- a' ) [lit] 96 + ;
: oa-id ( a -- a' ) [lit] 104 + ;

\ References: section, offset, kind, label index, addend as written (N).
[lit] 1024 constant oa-ref-cap
[lit] 40 constant oa-ref-size
create oa-refs oa-ref-cap oa-ref-size * allot
variable oa-ref-count
: oa-ref ( index -- a ) oa-ref-size * oa-refs + ;
[lit] 1 constant oa-rel8
[lit] 2 constant oa-pc32
[lit] 3 constant oa-plt32
[lit] 4 constant oa-abs64

\ The token being handled.
variable oa-ta
variable oa-tu
: oa-is? ( k n -- f )
  dup oa-tu @ = if, >r oa-ta @ swap r> bytes-eq exit, then,
  2drop [lit] 0 ;

\ oa-find ( a u -- index )  The label named a u, added if new.
variable oa-na
variable oa-nu
: oa-find
  oa-nu ! oa-na !
  oa-nu @ [lit] 64 < 0= if, [lit] 4 oa-die then,
  [lit] 0
  begin, dup oa-label-count @ < while,
    dup oa-label dup oa-len @ oa-nu @ = if,
      oa-na @ oa-nu @ bytes-eq if, exit, then,
    else, drop then,
    1+
  repeat,
  dup oa-label-cap < 0= if, [lit] 5 oa-die then,
  dup oa-label dup oa-label-size cc-obj-zero >r
  [lit] 0 begin, dup oa-nu @ < while,
    dup oa-na @ + c@ over r@ + c! 1+
  repeat, drop
  oa-nu @ r> oa-len !
  [lit] 1 oa-label-count +! ;

\ ----- hex bytes
: oa-hex ( c -- n )  \ -1 if c is not a hex digit
  dup [lit] 48 >= over [lit] 57 <= and if, [lit] 48 - exit, then,
  dup [lit] 97 >= over [lit] 102 <= and if, [lit] 87 - exit, then,
  dup [lit] 65 >= over [lit] 70 <= and if, [lit] 55 - exit, then,
  drop true ;
: oa-hex-at ( i -- n )
  oa-ta @ + c@ oa-hex dup 0< if, [lit] 1 oa-die then, ;
: oa-bytes
  oa-tu @ [lit] 1 and if, [lit] 1 oa-die then,
  [lit] 0 begin, dup oa-tu @ < while,
    dup oa-hex-at [lit] 16 * over 1+ oa-hex-at + cc-obj-byte
    [lit] 2 +
  repeat, drop ;

\ ----- NAME: and .globl NAME
: oa-define
  oa-ta @ oa-tu @ 1- oa-find oa-label
  dup oa-defined @ if, [lit] 2 oa-die then,
  true over oa-defined !
  cc-obj-current @ over oa-sec !
  cc-obj-here swap oa-off ! ;
: oa-globl
  token oa-tu ! oa-ta !
  oa-ta @ oa-tu @ oa-find oa-label oa-global true swap ! ;

\ ----- references: sigil, name, then an optional +N or -N in decimal
variable oa-kind
variable oa-name-end
variable oa-addend
: oa-sign? ( c -- f ) dup [lit] 43 = swap [lit] 45 = or ;
: oa-parse-addend ( i -- )  \ i indexes the sign
  [lit] 0 oa-addend !
  dup oa-tu @ = if, drop exit, then,
  dup oa-ta @ + c@ [lit] 45 = >r 1+
  dup oa-tu @ = if, [lit] 1 oa-die then,
  begin, dup oa-tu @ < while,
    dup oa-ta @ + c@ [lit] 48 -
    dup [lit] 0 < over [lit] 9 > or if, [lit] 1 oa-die then,
    oa-addend @ [lit] 10 * + oa-addend ! 1+
  repeat, drop
  r> if, [lit] 0 oa-addend @ - oa-addend ! then, ;
: oa-width ( kind -- bytes )
  dup oa-rel8 = if, drop [lit] 1 exit, then,
  oa-abs64 = if, [lit] 8 exit, then, [lit] 4 ;
: oa-reference ( kind -- )
  oa-kind !
  [lit] 1 begin, dup oa-tu @ < if, dup oa-ta @ + c@ oa-sign? 0= else, [lit] 0 then,
  while, 1+ repeat, oa-name-end !
  oa-name-end @ [lit] 1 = if, [lit] 1 oa-die then,
  oa-name-end @ oa-parse-addend
  oa-ref-count @ oa-ref-cap < 0= if, [lit] 5 oa-die then,
  oa-ref-count @ oa-ref >r
  cc-obj-current @ r@ !
  cc-obj-here r@ [lit] 8 + !
  oa-kind @ r@ [lit] 16 + !
  oa-ta @ 1+ oa-name-end @ 1- oa-find r@ [lit] 24 + !
  oa-addend @ r> [lit] 32 + !
  [lit] 1 oa-ref-count +!
  oa-kind @ oa-width begin, dup while, [lit] 0 cc-obj-byte 1- repeat, drop ;

\ ----- one token; true at }asm
create oa-k-end s, }asm
create oa-k-text s, .text
create oa-k-data s, .data
create oa-k-globl s, .globl
: oa-token ( -- done? )
  oa-k-end [lit] 4 oa-is? if, true exit, then,
  oa-k-text [lit] 5 oa-is? if, cc-obj-text cc-obj-use [lit] 0 exit, then,
  oa-k-data [lit] 5 oa-is? if, cc-obj-data cc-obj-use [lit] 0 exit, then,
  oa-k-globl [lit] 6 oa-is? if, oa-globl [lit] 0 exit, then,
  oa-ta @ c@
  dup [lit] 37 = if, drop oa-pc32 oa-reference [lit] 0 exit, then,
  dup [lit] 94 = if, drop oa-plt32 oa-reference [lit] 0 exit, then,
  dup [lit] 33 = if, drop oa-rel8 oa-reference [lit] 0 exit, then,
  [lit] 42 = if, oa-abs64 oa-reference [lit] 0 exit, then,
  oa-ta @ oa-tu @ + 1- c@ [lit] 58 = if, oa-define [lit] 0 exit, then,
  oa-bytes [lit] 0 ;

\ ----- }asm: symbols, then each reference resolved or relocated
: oa-symbols
  [lit] 0 begin, dup oa-label-count @ < while,
    dup oa-label >r
    r@ r@ oa-len @
    r@ oa-defined @ if,
      r@ oa-global @ if, cc-obj-global else, cc-obj-local then,
      cc-obj-notype cc-obj-default r@ oa-sec @ r@ oa-off @ [lit] 0
    else,
      cc-obj-global cc-obj-notype cc-obj-default cc-obj-undef [lit] 0 [lit] 0
    then,
    cc-obj-symbol r> oa-id !
    1+
  repeat, drop ;
variable oa-r
: oa-r-sec oa-r @ @ ;
: oa-r-off oa-r @ [lit] 8 + @ ;
: oa-r-kind oa-r @ [lit] 16 + @ ;
: oa-r-label oa-r @ [lit] 24 + @ oa-label ;
: oa-r-addend oa-r @ [lit] 32 + @ ;
: oa-local? ( -- f )
  oa-r-label oa-defined @ 0= if, [lit] 0 exit, then,
  oa-r-label oa-sec @ oa-r-sec = ;
\ S + N - (P + width): the displacement from the end of the field.
: oa-displacement ( -- n )
  oa-r-label oa-off @ oa-r-addend + oa-r-off - oa-r-kind oa-width - ;
: oa-resolve
  oa-r-kind oa-rel8 = if,
    oa-local? 0= if, [lit] 3 oa-die then,
    oa-displacement dup [lit] 0 [lit] 128 - < over [lit] 127 > or if, [lit] 3 oa-die then,
    [lit] 255 and oa-r-sec oa-r-off [lit] 1 cc-obj-patch exit,
  then,
  oa-r-kind oa-abs64 = if,
    oa-r-sec oa-r-off cc-obj-r64 oa-r-label oa-id @ oa-r-addend cc-obj-reloc exit,
  then,
  oa-local? if,
    oa-displacement [lit] 4294967295 and oa-r-sec oa-r-off cc-obj-patch-4le exit,
  then,
  oa-r-sec oa-r-off
  oa-r-kind oa-pc32 = if, cc-obj-pc32 else, cc-obj-plt32 then,
  oa-r-label oa-id @ oa-r-addend [lit] 4 - cc-obj-reloc ;
: oa-finish
  oa-symbols
  [lit] 0 begin, dup oa-ref-count @ < while,
    dup oa-ref oa-r ! oa-resolve 1+
  repeat, drop ;

: asm{
  [lit] 0 oa-label-count ! [lit] 0 oa-ref-count !
  begin,
    token dup 0= if, [lit] 6 oa-die then,
    oa-tu ! oa-ta !
    oa-token
  until,
  oa-finish ;
