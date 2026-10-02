\ Direct TinyCC source-only launcher, run from the repository root:
\     ./seed-forth < tools/tcc-start.fth
\ Prepare build-out/tcc-sources with tests/tcc/prep-stage-sources.py first.
\ Source preparation is outside this executable closure. This launcher loads
\ only Forth/C text and execs only the original seed. It does not run TinyCC,
\ invoke a shell, or claim a downstream runtime/self-hosting fixed point.
\ Output is build-out/tcc-seed; intermediates and diagnostics stay alongside it.
\ Minimal bootstrap vocabulary uses the same primitives as 010-lib.fth.
: here-addr latest [lit] 8 + ;
: c, here c! here-addr @ [lit] 1 + here-addr ! ;
: over >r dup r> swap ;
: - dup nand [lit] 1 + + ;
: 1+ [lit] 1 + ;
: 1- [lit] 1 - ;
: = - 0= ;
: <> = 0= ;
: 0< [lit] 9223372036854775808 / 0= 0= ;
: > swap - 0< ;
: 2dup over over ;
: 2drop drop drop ;
: immediate latest @ [lit] 8 + [lit] 1 swap c! ;
: ,4 dup c, [lit] 256 / dup c, [lit] 256 / dup c, [lit] 256 / c, ;
: ,8 dup ,4 [lit] 256 / [lit] 256 / [lit] 256 / [lit] 256 / ,4 ;
: push-body,
 [lit] 72 c, [lit] 131 c, [lit] 237 c, [lit] 8 c,
 [lit] 72 c, [lit] 137 c, [lit] 125 c, [lit] 0 c,
 [lit] 72 c, [lit] 191 c, ,8 [lit] 195 c, ;
: constant : push-body, [lit] 0 state ! ;
: call, [lit] 232 c, here [lit] 4 + - ,4 ;
' branch constant branch-xt
' 0branch constant 0branch-xt
: if, 0branch-xt call, here [lit] 0 , ; immediate
: then, here swap ! ; immediate
: begin, here ; immediate
: while, 0branch-xt call, here [lit] 0 , ; immediate
: repeat, swap branch-xt call, , here swap ! ; immediate
: create : here [lit] 19 + push-body, [lit] 0 state ! ;
: variable create [lit] 0 , ;
: allot here-addr @ + here-addr ! ;
: tib state [lit] 2048 - ;
: token
 tib [lit] 256 + tib
 begin, 2dup > while, [lit] 32 over c! 1+ repeat,
 2drop ' drop tib [lit] 0
 begin, 2dup + c@ [lit] 32 <> while, 1+ repeat, ;
: s0,
 token begin, dup while, over c@ c, 1- swap 1+ swap repeat,
 2drop [lit] 0 c, ;
: die [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 60 syscall6 ;
: open [lit] 0 [lit] 0 [lit] 0 [lit] 2 syscall6 ;
: read [lit] 0 [lit] 0 [lit] 0 [lit] 0 syscall6 ;
: write [lit] 0 [lit] 0 [lit] 0 [lit] 1 syscall6 ;
: close [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 3 syscall6 ;
: checked-close close if, [lit] 101 die then, ;
: unlink [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 87 syscall6 ;
: exec [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 59 syscall6 ;
create build-dir s0, build-out
create input-path s0, build-out/tcc-compile.input
create stdout-path s0, build-out/tcc-compile.stdout
create partial-path s0, build-out/tcc-seed.partial
create output-path s0, build-out/tcc-seed
create seed-path s0, ./seed-forth
create input-source s0, build-out/tcc-sources/direct-input.c
create compile-driver s0, tools/tcc-compile.fth
create f010 s0, 010-lib.fth
create f020 s0, 020-cc-arena.fth
create f030 s0, 030-cc-io.fth
create f040 s0, 040-cc-prep.fth
create f050 s0, 050-cc-lex.fth
create f060 s0, 060-cc-types.fth
create f070 s0, 070-cc-sym.fth
create f080 s0, 080-cc-elf.fth
create f090 s0, 090-cc-emit.fth
create f100 s0, 100-cc-expr.fth
create f110 s0, 110-cc-decl.fth
create f112 s0, 112-cc-stmt.fth
create f114 s0, 114-cc-func.fth
create f115 s0, 115-cc-native.fth
create f116 s0, 116-cc-prog.fth
create f117 s0, 117-cc-native-program.fth
create f118 s0, 118-cc-native-init.fth
create f119 s0, 119-cc-native-runtime.fth
create files
 f010 , f020 , f030 , f040 , f050 , f060 , f070 , f080 , f090 , f100 , f110 , f112 , f114 , f115 , f116 , f117 , f118 , f119 , compile-driver , input-source , [lit] 0 ,
create seed-argv seed-path , [lit] 0 ,
variable source-fd
variable output-fd
variable pointer
variable count
variable file-cursor
variable pid
variable status
\ Keep data above the fixed VM pages, addressed through STATE, not constants.
state [lit] 4096 + here-addr !
create buffer [lit] 65536 allot
: write-all
 count ! buffer pointer !
 begin, count @ while,
   output-fd @ pointer @ count @ write
   dup 0< if, [lit] 102 die then,
   dup 0= if, [lit] 103 die then,
   dup pointer @ + pointer ! count @ swap - count !
 repeat, ;
: append-file
 [lit] 0 [lit] 0 open dup 0< if, [lit] 104 die then, source-fd !
 begin,
   source-fd @ buffer [lit] 65536 read
   dup 0< if, [lit] 105 die then,
   dup
 while, write-all repeat, drop
 source-fd @ checked-close ;
: new-output
 [lit] 577 [lit] 384 open dup 0< if, [lit] 106 die then, output-fd ! ;
: remove-old
 unlink dup [lit] 0 [lit] 2 - = if, drop [lit] 0 then,
 if, [lit] 108 die then, ;
: main
 build-dir [lit] 493 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 83 syscall6
 dup [lit] 0 [lit] 17 - = if, drop [lit] 0 then,
 if, [lit] 107 die then,
 output-path remove-old partial-path remove-old
 input-path new-output
 files file-cursor !
 begin, file-cursor @ @ dup while,
   append-file file-cursor @ [lit] 8 + file-cursor !
 repeat, drop
 output-fd @ checked-close
 stdout-path new-output output-fd @ checked-close
 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 57 syscall6
 dup 0< if, [lit] 109 die then,
 dup 0= if,
   drop
   input-path [lit] 0 [lit] 0 open dup 0< if, [lit] 110 die then,
   dup source-fd ! [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 33 syscall6
   if, [lit] 111 die then,
   source-fd @ checked-close
   stdout-path [lit] 1 [lit] 0 open dup 0< if, [lit] 110 die then,
   dup source-fd ! [lit] 1 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 33 syscall6
   [lit] 1 <> if, [lit] 111 die then,
   source-fd @ checked-close
   seed-path seed-argv exec drop [lit] 112 die
 then,
 pid !
 pid @ status [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 61 syscall6
 pid @ <> if, [lit] 113 die then,
 status @ if, [lit] 114 die then,
 \ Unknown Forth words can otherwise print a diagnostic and leave status zero.
 stdout-path [lit] 0 [lit] 0 open dup 0< if, [lit] 110 die then,
 dup source-fd ! buffer [lit] 1 read
 if, [lit] 115 die then,
 source-fd @ checked-close
 partial-path [lit] 493 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 90 syscall6
 if, [lit] 116 die then,
 partial-path output-path [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 82 syscall6
 if, [lit] 117 die then,
 [lit] 0 die ;
main
