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
\ Depends on 010-lib.fth: constant, [lit], if,/then,/else,, +, -, *, /, =, dup,
\   swap, drop, and, >, 1+; 020-cc-arena.fth: cc-check-cap.

[lit] 0 constant ty-void
[lit] 1 constant ty-char
[lit] 2 constant ty-int                       \ signed 64-bit
[lit] 3 constant ty-struct
[lit] 4 constant ty-func

\ ty-make ( base ptrdepth -- ty )  Pack base and ptr-depth into one word.
: ty-make
  swap [lit] 65536 *  swap +  ;               \ (base << 16) | ptr-depth

\ ty-base ( ty -- base )  Extract the base kind (bits 16..31).
: ty-base
  [lit] 65536 /  [lit] 65535 and ;            \ shift right 16, mask low 16

\ ty-ptr ( ty -- depth )  Extract pointer depth (bits 0..7).
: ty-ptr
  [lit] 255 and ;

\ ty-size ( ty -- bytes )  sizeof(T) in bytes.
\ Pointers are always 8 bytes regardless of pointee.
\ Scalars: void=0, char=1, int/func default=8.
\ Struct sizes are NOT computed here — the caller resolves the descriptor
\ pointer (stored in the symbol entry's val) and reads its size field.
: ty-size
  dup ty-ptr [lit] 0 > if,
    drop [lit] 8
  else,
    ty-base
    dup ty-void = if, drop [lit] 0  else,
    dup ty-char = if, drop [lit] 1  else,
      drop [lit] 8                            \ int / struct / func
    then, then,
  then, ;

\ ===========================================================================
\ Struct descriptor accessors.
\ ===========================================================================
\ A struct descriptor (allocated via cc-alloc) has the layout:
\
\   offset  0:  total-size (bytes)
\   offset  8:  field-count
\   offset 16 + i*40:  field i record (5 cells)
\     +  0:  name-addr
\     +  8:  name-len
\     + 16:  field type
\     + 24:  field offset (bytes from struct base)
\     + 32:  pointee struct descriptor (0 unless the field is a struct pointer)
\
\ The header is 16 bytes; each field record is 40 bytes.  Capped at 16 fields
\ per struct (descriptor size cc-sd-bytes = 16 + 40*16 = 656 bytes).  The
\ pointee field enables chained '->' / '.' postfix on fields that are
\ themselves struct pointers (e.g. `head->next->prev` resolves both arrows).

[lit] 16 constant cc-sd-max-fields
cc-sd-max-fields [lit] 40 * [lit] 16 + constant cc-sd-bytes      \ 656

: cc-sd-total-size      @ ;                            \ ( desc -- size )
: cc-sd-field-count     [lit] 8 + @ ;                  \ ( desc -- n )
: cc-sd-set-total-size  ! ;                            \ ( v desc -- )
: cc-sd-set-field-count [lit] 8 + ! ;                  \ ( v desc -- )

\ cc-sd-field-rec ( desc i -- rec-addr )  Address of field i's record.
\ Dies with code 50 for i past the last record: a struct with more than
\ cc-sd-max-fields fields.
: cc-sd-field-rec
  dup 1+ cc-sd-max-fields [lit] 50 cc-check-cap
  [lit] 40 * [lit] 16 + + ;

\ Field-record accessors / mutators.  Each takes rec-addr on TOS.
: cc-sf-name-addr       @ ;                            \ ( rec -- a )
: cc-sf-name-len        [lit]  8 + @ ;                 \ ( rec -- u )
: cc-sf-type            [lit] 16 + @ ;                 \ ( rec -- ty )
: cc-sf-offset          [lit] 24 + @ ;                 \ ( rec -- off )
: cc-sf-desc            [lit] 32 + @ ;                 \ ( rec -- desc )

: cc-sf-set-name-addr   ! ;                            \ ( a rec -- )
: cc-sf-set-name-len    [lit]  8 + ! ;                 \ ( u rec -- )
: cc-sf-set-type        [lit] 16 + ! ;                 \ ( ty rec -- )
: cc-sf-set-offset      [lit] 24 + ! ;                 \ ( off rec -- )
: cc-sf-set-desc        [lit] 32 + ! ;                 \ ( desc rec -- )
