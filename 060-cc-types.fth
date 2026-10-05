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
[lit] 14 constant ty-array
\ LP64 long long kinds share long's representation but not its identity:
\ only the LP64 data model spells them, and they rank above long.
[lit] 15 constant ty-llong
[lit] 16 constant ty-ullong

\ Array nodes carry element type/descriptor, dimensions, size and alignment.
\ The last cell is true when the elements are qualified: a pointer to the
\ node then points to qualified elements, as a pointer to const T would.
: cc-ad-type @ ;
: cc-ad-desc [lit] 8 + @ ;
: cc-ad-count [lit] 16 + @ ;
: cc-ad-inner [lit] 24 + @ ;
: cc-ad-size [lit] 32 + @ ;
: cc-ad-align [lit] 40 + @ ;
: cc-ad-qualified [lit] 48 + @ ;

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
\ Both long long kinds take the final eight-byte answer, exactly as long.
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
  over ty-uint = or over ty-ulong = or over ty-ullong = or
  swap ty-char = cc-target-lp64 @ 0= and or ;

\ ty-long-long? ( ty -- flag )  Scalar long long, signed or unsigned.
: ty-long-long?
  dup ty-ptr if, drop [lit] 0 exit, then,
  ty-base dup ty-llong = swap ty-ullong = or ;

\ ty-align ( ty -- bytes )  Scalar/pointer alignment; void uses 1.
\ Struct/union alignment is cc-sd-align, not the type word's fallback.
: ty-align  ty-size dup 0= if, drop [lit] 1 then, ;

\ cc-integer-literal-type ( -- ty )  Type of the current tk-num token.
\ The original spelling (050) distinguishes decimal from hex/octal and
\ preserves U/L/LL suffixes without expanding the lexer's snapshot state.
\ LP64 long and long long share one 64-bit representation, so only a
\ two-letter LL suffix selects long long; its value picks the signedness.
\ As a bootstrap extension, a decimal value beyond signed long uses ulong.
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
      [lit] 1 cc-literal-long +!
    then,
    swap 1+ swap 1-
  repeat, drop drop
  cc-literal-long @ [lit] 1 > if,
    cc-literal-unsigned @ tok-num @ 2^63 / or if,
      ty-ullong
    else, ty-llong then,
    [lit] 0 ty-make exit,
  then,
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
\ A struct/union descriptor (allocated via cc-sd-alloc) is a fixed header
\ whose address never changes, plus a separately allocated field table:
\
\   offset  0: total-size (bytes)
\   offset  8: field-count
\   offset 16: aggregate alignment (LP64)
\   offset 24: is-union flag (LP64)
\   offset 32: target cell (SysV: bitfield cursor, 129-cc-bitfield.fth)
\   offset 40: field-table address (0 until the first field)
\   offset 48: field-table capacity, in records
\
\ Field i's record is at table + i*record-bytes.  LP64 records are 6 cells:
\     +  0: name-addr
\     +  8: name-len
\     + 16: field type (array element type when array-len is nonzero)
\     + 24: field offset (bytes from aggregate base)
\     + 32: aggregate/pointee descriptor, or 0
\     + 40: array length (0 for a scalar)
\
\ Legacy records keep only the first five cells (40 bytes) and legacy
\ code reads only the first two header cells.  The table starts with room
\ for 8 records and doubles when an append needs more, so small structs
\ stay small and a large one costs at most twice its exact size.  The cap
\ is policy, not storage: LP64 allows 1023 members, C99's translation
\ limit for one struct or union (5.2.4.1).  That is over four times the
\ largest in GCC 4.0.4 (JNINativeInterface, 232 members) and seven times
\ bfd's (elf_backend_data, 143).  The legacy M2-Planet subset
\ keeps its documented 16-field limit and small arena.

[lit] 16 constant cc-sd-max-fields
[lit] 1023 constant cc-sd-lp64-max-fields
[lit] 56 constant cc-sd-header-bytes
[lit] 8 constant cc-sd-initial-fields

: cc-sd-field-cap
  cc-target-lp64 @ if, cc-sd-lp64-max-fields else, cc-sd-max-fields then, ;

: cc-sd-record-bytes-default
  cc-target-lp64 @ if, [lit] 48 else, [lit] 40 then, ;
defer cc-sd-record-bytes
' cc-sd-record-bytes-default is cc-sd-record-bytes

\ cc-zalloc ( bytes -- addr )  Arena storage cleared to zero, so cells a
\ target adds read as 0 even where the arena reuses mapped memory.
: cc-zalloc
  dup cc-alloc                                   ( bytes addr )
  dup >r swap over +                             ( start end ; R: addr )
  begin, over over < while,
    swap [lit] 0 over c! 1+ swap
  repeat,
  drop drop r> ;

\ cc-sd-alloc ( -- desc )  A zeroed header with no field table yet.
: cc-sd-alloc  cc-sd-header-bytes cc-zalloc ;

: cc-sd-total-size      @ ;                            \ ( desc -- size )
: cc-sd-field-count     [lit] 8 + @ ;                  \ ( desc -- n )
: cc-sd-align           [lit] 16 + @ ;                 \ ( desc -- align )
: cc-sd-union?          [lit] 24 + @ ;                 \ ( desc -- flag )
: cc-sd-set-total-size  ! ;                            \ ( v desc -- )
: cc-sd-set-field-count [lit] 8 + ! ;                  \ ( v desc -- )
: cc-sd-set-align       [lit] 16 + ! ;                 \ ( v desc -- )
: cc-sd-set-union       [lit] 24 + ! ;                 \ ( v desc -- )
: cc-sd-table           [lit] 40 + @ ;                 \ ( desc -- addr )
: cc-sd-table-cap       [lit] 48 + @ ;                 \ ( desc -- n )

\ cc-sd-grow ( desc need -- )  Replace the table with a zeroed one holding
\ at least need records (double, at least 8, at most the field cap) and
\ copy the old records across.  The old table stays behind in the arena,
\ so a record address taken before an append to the same descriptor is
\ stale afterwards; callers fetch each record after any such append.
\ cc-sd-table-moved ( old new bytes -- ) lets side tables keyed by record
\ address follow the records (115-cc-native.fth: field qualification).
: cc-sd-table-moved-default  drop 2drop ;
defer cc-sd-table-moved
' cc-sd-table-moved-default is cc-sd-table-moved
variable cc-sd-grow-desc
: cc-sd-grow
  swap cc-sd-grow-desc !                         ( need )
  cc-sd-grow-desc @ cc-sd-table-cap [lit] 2 *    ( need cap )
  dup cc-sd-initial-fields < if, drop cc-sd-initial-fields then,
  begin, over over > while, [lit] 2 * repeat,
  nip dup cc-sd-field-cap > if, drop cc-sd-field-cap then,
  dup cc-sd-record-bytes * cc-zalloc             ( cap new )
  cc-sd-grow-desc @ cc-sd-table over             ( cap new old new )
  cc-sd-grow-desc @ cc-sd-table-cap cc-sd-record-bytes *
  begin, dup while,                              ( cap new src dst n )
    >r over c@ over c! 1+ swap 1+ swap r> 1-
  repeat, drop 2drop                             ( cap new )
  cc-sd-grow-desc @ cc-sd-table over
  cc-sd-grow-desc @ cc-sd-table-cap cc-sd-record-bytes * cc-sd-table-moved
  cc-sd-grow-desc @ [lit] 40 + !
  cc-sd-grow-desc @ [lit] 48 + ! ;

\ cc-sd-field-rec ( desc i -- rec-addr )  Error 50 if record i would exceed
\ the target's member cap; grow the table when i is past its capacity.
: cc-sd-field-rec
  dup 1+ cc-sd-field-cap [lit] 50 cc-check-cap
  over cc-sd-table-cap over > 0= if, over over 1+ cc-sd-grow then,
  cc-sd-record-bytes * swap cc-sd-table + ;

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

\ Targets may extend field shape without changing legacy/native records.
: cc-sf-array-inner-default ( rec -- n ) drop [lit] 0 ;
: cc-sf-set-array-inner-default ( n rec -- )
  drop if, [lit] 213 cc-die then, ;
defer cc-sf-array-inner
defer cc-sf-set-array-inner
' cc-sf-array-inner-default is cc-sf-array-inner
' cc-sf-set-array-inner-default is cc-sf-set-array-inner
