\ 060-cc-types.fth — C type encoding for the C-subset compiler.
\
\ A type is one machine word:
\   bits[ 0.. 7] = pointer depth (0 = scalar T, 1 = T*, 2 = T**, ...)
\   bits[ 8..15] = always 0
\   bits[16..31] = base kind (one of ty-* below)
\
\ Struct and function types use base = ty-struct / ty-func.  The type word
\ does not say which struct: the descriptor pointer lives in the symbol
\ table — the tag's sk-struct entry keeps it in val, and a struct-typed
\ variable keeps it in its struct-desc cell (070-cc-sym.fth) — and in a
\ field record's pointee slot (below).  The caller resolves it before any
\ size-of/field-offset query.
\
\ Depends on 010-lib.fth: constant, variable, [lit], if,/then,/else,, exit,,
\   begin,/while,/repeat,, +, -, *, /, =, dup, swap, drop, and, or, >, 1+,
\   @, !, c!, over; 020-cc-arena.fth: cc-check-cap, cc-alloc.

[lit] 0 constant ty-void
[lit] 1 constant ty-char
[lit] 2 constant ty-int                       \ legacy 64-bit; LP64 32-bit
[lit] 3 constant ty-struct
[lit] 4 constant ty-func
[lit] 5 constant ty-short
[lit] 6 constant ty-long
[lit] 7 constant ty-float
[lit] 8 constant ty-double
[lit] 9 constant ty-uchar
[lit] 10 constant ty-ushort
[lit] 11 constant ty-uint
[lit] 12 constant ty-ulong
[lit] 13 constant ty-ldouble

\ The pinned M2/pnut route keeps the original data model unless opted in.
variable cc-target-lp64
[lit] 0 cc-target-lp64 !

\ Restricted first-stage bootstrap approximation, never the default ABI.
\ Portable bootstrap float values travel as integer bits in 8-byte cells.
\ This flag does not implement IEEE floating arithmetic or conversions.
variable cc-bootstrap-floatbits
[lit] 0 cc-bootstrap-floatbits !

\ ty-make ( base ptrdepth -- ty )  Pack base and ptr-depth into one word.
: ty-make
  swap [lit] 65536 *  swap +  ;               \ (base << 16) | ptr-depth

\ ty-base ( ty -- base )  Extract the base kind (bits 16..31).
: ty-base
  [lit] 65536 /  [lit] 65535 and ;            \ shift right 16, mask low 16

\ ty-ptr ( ty -- depth )  Extract pointer depth (bits 0..7).
: ty-ptr
  [lit] 255 and ;

\ ty-size ( ty -- bytes )  Scalar/pointer storage size, not aggregate size.
\ The caller resolves struct descriptors before asking their size/alignment.
\ LP64 is the AMD64 System V model: int=4, long/pointer=8, long double=16.
\ The default retains the original char=1 and other non-void scalars=8.
: ty-size
  dup ty-ptr [lit] 0 > if, drop [lit] 8 exit, then,
  ty-base
  dup ty-void = if, drop [lit] 0 exit, then,
  dup ty-char = if, drop [lit] 1 exit, then,
  cc-target-lp64 @ if,
    cc-bootstrap-floatbits @ if,
      dup ty-float = over ty-double = or over ty-ldouble = or if,
        drop [lit] 8 exit,
      then,
    then,
    dup ty-uchar = if, drop [lit] 1 exit, then,
    dup ty-short = over ty-ushort = or if, drop [lit] 2 exit, then,
    dup ty-int = over ty-uint = or over ty-float = or if,
      drop [lit] 4 exit,
    then,
    dup ty-ldouble = if, drop [lit] 16 exit, then,
  then,
  drop [lit] 8 ;

\ ty-unsigned? ( ty -- flag )  Pointers compare as unsigned addresses.
\ Plain char is signed in LP64; legacy byte expressions are zero-extended.
: ty-unsigned?
  dup ty-ptr [lit] 0 > if, drop true exit, then,
  ty-base
  dup ty-uchar = over ty-ushort = or
  over ty-uint = or over ty-ulong = or
  swap ty-char = cc-target-lp64 @ 0= and or ;

\ ty-align ( ty -- bytes )  Scalar/pointer alignment; void uses 1.
\ Struct/union alignment is cc-sd-align, not the type word's fallback.
: ty-align  ty-size dup 0= if, drop [lit] 1 then, ;

\ cc-integer-literal-type ( -- ty )  Type of the current tk-num token.
\ The original spelling (050) distinguishes decimal from hex/octal and
\ preserves U/L/LL suffixes without expanding the lexer's snapshot state.
\ LP64 treats long and long long as the same 64-bit representation.  As a
\ bootstrap extension, a decimal value beyond signed long uses ulong.
\ Range tests use unsigned division, so bit-63-set constants stay correct.
variable cc-literal-unsigned
variable cc-literal-long
: cc-integer-literal-type
  cc-target-lp64 @ 0= if, ty-int [lit] 0 ty-make exit, then,
  [lit] 0 cc-literal-unsigned ! [lit] 0 cc-literal-long !
  tok-str-addr @ tok-str-len @                    ( addr len )
  begin, dup [lit] 0 > while,
    over c@
    dup [char] u = over [char] U = or if,
      true cc-literal-unsigned !
    then,
    dup [char] l = swap [char] L = or if,
      true cc-literal-long !
    then,
    swap 1+ swap 1-
  repeat, drop drop
  cc-literal-long @ if,
    cc-literal-unsigned @ tok-num @ 2^63 / or if,
      ty-ulong
    else, ty-long then,
  else,
    cc-literal-unsigned @ if,
      tok-num @ [lit] 4294967296 / if, ty-ulong else, ty-uint then,
    else,
      tok-num @ [lit] 2147483648 / 0= if,
        ty-int
      else,
        tok-str-addr @ c@ [char] 0 =
        tok-num @ [lit] 4294967296 / 0= and if,
          ty-uint
        else,
          tok-num @ 2^63 / if, ty-ulong else, ty-long then,
        then,
      then,
    then,
  then,
  [lit] 0 ty-make ;

\ ===========================================================================
\ Struct descriptor accessors.
\ ===========================================================================
\ LP64 struct/union descriptors (allocated via cc-sd-alloc) have this layout:
\
\   offset  0: total-size (bytes)
\   offset  8: field-count
\   offset 16: aggregate alignment (LP64)
\   offset 24: is-union flag (LP64)
\   offset 32 + i*48: field i record (6 cells)
\     +  0: name-addr
\     +  8: name-len
\     + 16: field type (array element type when array-len is nonzero)
\     + 24: field offset (bytes from aggregate base)
\     + 32: aggregate/pointee descriptor, or 0
\     + 40: array length (0 for a scalar)
\
\ Legacy descriptors retain a 16-byte header, 40-byte field records, and a
\ 16-field limit.  Only the first two header cells and first five record
\ cells exist there.  LP64 permits 128 fields and the additional metadata.
\ Both the legacy compiler arena budget and its emitted layout stay intact.

[lit] 16 constant cc-sd-max-fields
[lit] 128 constant cc-sd-lp64-max-fields
cc-sd-max-fields [lit] 40 * [lit] 16 + constant cc-sd-bytes

: cc-sd-field-cap
  cc-target-lp64 @ if, cc-sd-lp64-max-fields else, cc-sd-max-fields then, ;

: cc-sd-allocation-bytes
  cc-target-lp64 @ if,
    cc-sd-lp64-max-fields [lit] 48 * [lit] 32 +
  else, cc-sd-bytes then, ;

\ cc-sd-alloc ( -- desc )  Clear reused arena storage, including new cells.
: cc-sd-alloc
  cc-sd-allocation-bytes dup cc-alloc             ( bytes desc )
  dup >r swap over +                             ( start end ; R: desc )
  begin, over over < while,
    swap [lit] 0 over c! 1+ swap
  repeat,
  drop drop r> ;

: cc-sd-total-size      @ ;                            \ ( desc -- size )
: cc-sd-field-count     [lit] 8 + @ ;                  \ ( desc -- n )
: cc-sd-align           [lit] 16 + @ ;                 \ ( desc -- align )
: cc-sd-union?          [lit] 24 + @ ;                 \ ( desc -- flag )
: cc-sd-set-total-size  ! ;                            \ ( v desc -- )
: cc-sd-set-field-count [lit] 8 + ! ;                  \ ( v desc -- )
: cc-sd-set-align       [lit] 16 + ! ;                 \ ( v desc -- )
: cc-sd-set-union       [lit] 24 + ! ;                 \ ( v desc -- )

\ cc-sd-field-rec ( desc i -- rec-addr )  Check before accessing a record.
\ Error 50 remains the legacy 17th-field failure; LP64's limit is larger.
: cc-sd-field-rec
  dup 1+ cc-sd-field-cap [lit] 50 cc-check-cap
  cc-target-lp64 @ if, [lit] 48 * [lit] 32 +
  else, [lit] 40 * [lit] 16 + then, + ;

\ Field-record accessors / mutators.  Each takes rec-addr on TOS.
\ Alignment, union and array-length accessors are for LP64 descriptors only.
: cc-sf-name-addr       @ ;                            \ ( rec -- a )
: cc-sf-name-len        [lit]  8 + @ ;                 \ ( rec -- u )
: cc-sf-type            [lit] 16 + @ ;                 \ ( rec -- ty )
: cc-sf-offset          [lit] 24 + @ ;                 \ ( rec -- off )
: cc-sf-desc            [lit] 32 + @ ;                 \ ( rec -- desc )
: cc-sf-array-len       [lit] 40 + @ ;                 \ ( rec -- n )

: cc-sf-set-name-addr   ! ;                            \ ( a rec -- )
: cc-sf-set-name-len    [lit]  8 + ! ;                 \ ( u rec -- )
: cc-sf-set-type        [lit] 16 + ! ;                 \ ( ty rec -- )
: cc-sf-set-offset      [lit] 24 + ! ;                 \ ( off rec -- )
: cc-sf-set-desc        [lit] 32 + ! ;                 \ ( desc rec -- )
: cc-sf-set-array-len   [lit] 40 + ! ;                 \ ( n rec -- )
