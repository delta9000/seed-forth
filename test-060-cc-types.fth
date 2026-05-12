\ test-060-cc-types.fth — smoke test for 060-cc-types.fth.
\ Run via:
\   cat 010-lib.fth 020-cc-arena.fth 030-cc-io.fth 040-cc-prep.fth 050-cc-lex.fth \
\       060-cc-types.fth test-060-cc-types.fth | strip_forth | ./seed-forth ; echo $?
\
\ AND-accumulator pattern: first comparison seeds the accumulator,
\ subsequent ones AND themselves in.  Final `0= die` turns acc=-1
\ into exit 0, acc=0 into exit 255.

\ ===========================================================================
\ ty-make / ty-base / ty-ptr round-trips
\ ===========================================================================

\ int as scalar: base=ty-int, ptr=0
ty-int [lit] 0 ty-make
dup ty-base ty-int =                                   \ seed accumulator
swap ty-ptr [lit] 0 =                              and

\ char as ptr (char*): base=ty-char, ptr=1
ty-char [lit] 1 ty-make
dup ty-base ty-char =                              and
swap ty-ptr [lit] 1 =                              and

\ int** (depth 2)
ty-int [lit] 2 ty-make
dup ty-base ty-int =                               and
swap ty-ptr [lit] 2 =                              and

\ struct base
ty-struct [lit] 0 ty-make
dup ty-base ty-struct =                            and
swap ty-ptr [lit] 0 =                              and

\ ===========================================================================
\ ty-size
\ ===========================================================================

ty-int  [lit] 0 ty-make ty-size [lit] 8 =          and  \ int    -> 8
ty-char [lit] 0 ty-make ty-size [lit] 1 =          and  \ char   -> 1
ty-char [lit] 1 ty-make ty-size [lit] 8 =          and  \ char*  -> 8
ty-void [lit] 0 ty-make ty-size [lit] 0 =          and  \ void   -> 0
ty-int  [lit] 5 ty-make ty-size [lit] 8 =          and  \ T***** -> 8

\ ===========================================================================
\ Final exit
\ ===========================================================================
0= die
