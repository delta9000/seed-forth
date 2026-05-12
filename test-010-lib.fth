\ test-010-lib.fth — comparison-ops smoke test for 010-lib.fth.
\
\ Test pattern: each line evaluates a comparison expression that must leave
\ -1 (true) on the stack.  The first test seeds the accumulator; every
\ subsequent test combines its flag via `and` so the final TOS is -1 only
\ if every test passed.  We then 0= the accumulator and pass it through
\ sys_exit.  Linux exit takes the low 8 bits:
\   all-pass: acc = -1, 0= -> 0, exit code 0.
\   any-fail: acc =  0, 0= -> -1 (low byte 0xFF = 255), exit code 255.
\
\ Run via:  cat 010-lib.fth test-010-lib.fth | strip_forth | ./seed-forth
\           echo $?    # 0 = pass, nonzero = fail

\ ----- = and <> -----
[lit] 5 [lit] 5 =                              \ pass: 5=5
[lit] 5 [lit] 6 = 0=                       and \ pass: 5<>6
[lit] 0 [lit] 0 =                          and \ pass: 0=0
[lit] 5 [lit] 6 <>                         and \ pass: 5<>6
[lit] 5 [lit] 5 <> 0=                      and \ pass: !(5<>5)

\ ----- neg-flag -----
[lit] 0 neg-flag 0=                        and \ pass:  0 not negative
[lit] 1 neg-flag 0=                        and \ pass: +1 not negative
[lit] 9223372036854775807 neg-flag 0=      and \ pass:  MAX_INT64 not negative
[lit] 9223372036854775808 neg-flag         and \ pass:  MIN_INT64 (= -2^63) is negative

\ ----- < and > -----
[lit] 5 [lit] 6 <                          and \ pass: 5<6
[lit] 6 [lit] 5 < 0=                       and \ pass: !(6<5)
[lit] 5 [lit] 5 < 0=                       and \ pass: !(5<5)
[lit] 7 [lit] 5 >                          and \ pass: 7>5
[lit] 5 [lit] 7 > 0=                       and \ pass: !(5>7)
[lit] 5 [lit] 5 > 0=                       and \ pass: !(5>5)

\ ----- <= and >= -----
[lit] 5 [lit] 5 <=                         and \ pass: 5<=5
[lit] 5 [lit] 6 <=                         and \ pass: 5<=6
[lit] 6 [lit] 5 <= 0=                      and \ pass: !(6<=5)
[lit] 5 [lit] 5 >=                         and \ pass: 5>=5
[lit] 6 [lit] 5 >=                         and \ pass: 6>=5
[lit] 5 [lit] 6 >= 0=                      and \ pass: !(5>=6)

\ ----- Stack shuffles -----

\ nip ( a b -- b )
[lit] 1 [lit] 2 nip [lit] 2 =              and \ keeps b

\ rot ( a b c -- b c a ) -- check TOS=a, NOS=c, 3rd=b
[lit] 1 [lit] 2 [lit] 3 rot
  [lit] 1 = swap [lit] 3 = and swap [lit] 2 = and  and

\ 2dup ( a b -- a b a b )
[lit] 7 [lit] 8 2dup
  [lit] 8 = swap [lit] 7 = and swap [lit] 8 = and swap [lit] 7 = and  and

\ 2drop ( a b -- )  push then drop, then synthesize -1 and AND with acc.
[lit] 1 [lit] 2 2drop
[lit] 0 0=                                 and \ -1 onto stack, AND with acc

\ ----- +! and -!  using HERE as a writable scratch cell -----
here [lit] 7 swap !                            \ store 7 at HERE
[lit] 3 here +! here @ [lit] 10 =          and \ 7 + 3 = 10
[lit] 4 here -! here @ [lit]  6 =          and \ 10 - 4 = 6

\ ----- Control-flow combinators -----
\ Each test defines a colon word that uses one of the combinators, then
\ exercises both branches and AND-folds the result into the accumulator.

\ ift ( f -- n )  if-then: keeps 7 if false, replaces with 100 if true.
: ift  [lit] 7 swap if, drop [lit] 100 then, ;
[lit] 0  0= ift [lit] 100 =                and \ true  -> body ran -> 100
[lit] 0     ift [lit] 7   =                and \ false -> body skipped -> 7

\ choose ( f -- n )  if-else-then: 1 if true, 2 if false.
: choose  if, [lit] 1 else, [lit] 2 then, ;
[lit] 0  0= choose [lit] 1 =               and \ true  -> 1
[lit] 0     choose [lit] 2 =               and \ false -> 2

\ count-while ( n -- 0 )  begin/while/repeat decrement loop.
: count-while  begin, dup [lit] 0 > while, [lit] 1 - repeat, ;
[lit] 7 count-while [lit] 0 =              and
[lit] 0 count-while [lit] 0 =              and \ zero-iteration case

\ ----- constant / variable / allot / create -----

\ constant: word pushes its compile-time value at runtime.
[lit] 1234567 constant my-c
my-c [lit] 1234567 =                       and

\ Two constants in a row, to verify STATE got reset.
[lit] 7 constant seven
seven [lit] 7 =                            and

\ variable: store / fetch.
variable my-v
[lit] 42 my-v !
my-v @ [lit] 42 =                          and
[lit] 8 my-v +!
my-v @ [lit] 50 =                          and

\ create + ,: layered storage.
create my-arr
[lit] 100 ,
[lit] 200 ,
[lit] 300 ,
my-arr           @ [lit] 100 =             and
my-arr [lit]  8 + @ [lit] 200 =            and
my-arr [lit] 16 + @ [lit] 300 =            and

\ allot: bump HERE without writing.
here [lit] 32 allot here swap - [lit] 32 = and

\ ----- exit with derived code -----
\ acc=-1 (all pass) -> 0= -> 0 -> exit 0.
\ acc= 0 (any fail) -> 0= -> -1 -> exit 255.
0= die
