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

\ ----- 0< -----
[lit] 0 0< 0=                              and \ pass:  0 not negative
[lit] 1 0< 0=                              and \ pass: +1 not negative
[lit] 9223372036854775807 0< 0=            and \ pass:  MAX_INT64 not negative
[lit] 9223372036854775808 0<               and \ pass:  MIN_INT64 (= -2^63) is negative

\ ----- true, 1+, 1- -----
true [lit] 0 0= =                          and \ true is -1
[lit] 5 1+ [lit] 6 =                       and
[lit] 5 1- [lit] 4 =                       and

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

\ until, ( n -- 0 )  post-test loop: body runs at least once.
: count-until  begin, 1- dup 0= until, ;
[lit] 3 count-until [lit] 0 =              and

\ again, + exit, : the only way out of an again, loop is exit,.
: count-again  begin, dup 0= if, exit, then, 1- again, ;
[lit] 4 count-again [lit] 0 =              and

\ exit, inside if, : early return.
: sign3  dup 0< if, drop [lit] 1 exit, then, 0= if, [lit] 2 exit, then, [lit] 3 ;
[lit] 0 1- sign3 [lit] 1 =                 and
[lit] 0    sign3 [lit] 2 =                 and
[lit] 9    sign3 [lit] 3 =                 and

\ ----- char, [char] and the named characters -----
char A [lit] 65 =                          and \ interpret mode
: semi [char] ; ;
semi [lit] 59 =                            and \ compile mode
: quote [char] " ;
quote [lit] 34 =                           and
: word1 [char] xyz ;
word1 [lit] 120 =                          and \ first byte of the token
bl [lit] 32 =  nl [lit] 10 = and  tab [lit] 9 = and  and
lparen [lit] 40 =  backslash [lit] 92 = and        and

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

\ variable starts at 0.
variable my-z
my-z @ [lit] 0 =                           and

\ bytes-eq: equal, differ early, differ late, zero length.
create be1  char a c, char b c, char c c,
create be2  char a c, char b c, char c c,
create be3  char x c, char b c, char c c,
create be4  char a c, char b c, char x c,
be1 be2 [lit] 3 bytes-eq                   and
be1 be3 [lit] 3 bytes-eq 0=                and
be1 be4 [lit] 3 bytes-eq 0=                and
be1 be4 [lit] 2 bytes-eq                   and
be1 be3 [lit] 0 bytes-eq                   and

\ s, lays down a token's bytes; token also leaves its length.
create s1  s, abc
be1 s1 [lit] 3 bytes-eq                    and
: tl token nip ; tl hello [lit] 5 =       and

\ allot: bump HERE without writing.
here [lit] 32 allot here swap - [lit] 32 = and

\ ----- exit with derived code -----
\ acc=-1 (all pass) -> 0= -> 0 -> exit 0.
\ acc= 0 (any fail) -> 0= -> -1 -> exit 255.
0= die
