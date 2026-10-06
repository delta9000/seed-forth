\ Python-free bootstrap of the native compiler driver. From the repository root:
\     ./seed-forth < tools/seed-cc-start.fth
\ writes build-out/seed-cc/seed-cc and build-out/seed-cc/seed-ar (scratch in
\ build-out/seed-cc/boot/). The seed is the only executable that runs: this
\ file forks and execs ./seed-forth once per step, feeding each a file that
\ concatenates the Forth compiler layers, a fixed driver from
\ tools/seed-cc-boot/ and one C source. Steps, as tools/seed-cc.c does them:
\   1. compile every runtime/gcc-seed/*.c except math.c, then tools/seed-cc.c
\      and tools/seed-ar.c; compiler layers are 010-lib.fth and the sorted
\      NNN-cc-*.fth except 120-cc-main.fth and 140-cc-link.fth
\   2. write the seven Forth runtime objects (syscall ... longjmp)
\   3. archive every runtime object except start.o into libseed.a, sorted
\      sources first, then the Forth objects
\   4. link start.o, the program object and libseed.a, for each program
\ Both directories are listed with getdents64, so new runtime files and
\ compiler layers are picked up without editing this file. Exit status 0 is
\ success; 1xx codes identify the failing operation below.
\ Minimal defining/control words below use the same primitives as 010-lib.fth.
: here-addr latest [lit] 8 + ;
: c, here c! here-addr @ [lit] 1 + here-addr ! ;
: over >r dup r> swap ;
: nip swap drop ;
: - dup nand [lit] 1 + + ;
: 1+ [lit] 1 + ;
: 1- [lit] 1 - ;
: = - 0= ;
: <> = 0= ;
: and nand dup nand ;
: 0< [lit] 9223372036854775808 / 0= 0= ;
: < - 0< ;
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
: else, branch-xt call, here [lit] 0 , swap here swap ! ; immediate
: begin, here ; immediate
: while, 0branch-xt call, here [lit] 0 , ; immediate
: repeat, swap branch-xt call, , here swap ! ; immediate
: exit, [lit] 195 c, ; immediate
: create : here [lit] 19 + push-body, [lit] 0 state ! ;
: variable create [lit] 0 , ;
: allot here-addr @ + here-addr ! ;
: tib state [lit] 2048 - ;
: 2dup over over ;
: > swap < ;
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
: getdents [lit] 0 [lit] 0 [lit] 0 [lit] 217 syscall6 ;
: mkdir [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 83 syscall6 ;
: rename [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 82 syscall6 ;
: exec [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 59 syscall6 ;
: wait4 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 61 syscall6 ;
: fork [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 57 syscall6 ;
: dup2 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 33 syscall6 ;
: checked-close close if, [lit] 101 die then, ;
\ Fixed names. Every path is relative to the repository root.
create d-build s0, build-out
create d-out s0, build-out/seed-cc
create d-boot s0, build-out/seed-cc/boot
create d-root s0, .
create d-runtime s0, runtime/gcc-seed
create boot-prefix s0, build-out/seed-cc/boot/
create runtime-prefix s0, runtime/gcc-seed/
create tools-prefix s0, tools/
create input-path s0, build-out/seed-cc/boot/input
create unit-object s0, build-out/seed-cc/boot/unit.o
create seed-path s0, ./seed-forth
create seed-argv seed-path , [lit] 0 ,
create f010 s0, 010-lib.fth
create f020 s0, 020-cc-arena.fth
create f030 s0, 030-cc-io.fth
create f081 s0, 081-cc-object.fth
create f122 s0, 122-cc-sysv-runtime.fth
create f140 s0, 140-cc-link.fth
create f141 s0, 141-archive.fth
create runtime-unit s0, tools/seed-cc-boot/runtime-unit.fth
create tools-unit s0, tools/seed-cc-boot/tools-unit.fth
create sysrt-driver s0, tools/seed-cc-boot/sysrt.fth
create archive-head s0, tools/seed-cc-boot/archive-head.fth
create archive-tail s0, tools/seed-cc-boot/archive-tail.fth
create link-cc s0, tools/seed-cc-boot/link-seed-cc.fth
create link-ar s0, tools/seed-cc-boot/link-seed-ar.fth
create seed-cc-c s0, seed-cc.c
create seed-ar-c s0, seed-ar.c
create k-cc s0, -cc-
create k-fth s0, .fth
create k-main s0, 120-cc-main.fth
create k-link s0, 140-cc-link.fth
create k-dot-c s0, .c
create k-math s0, math.c
create k-dot-o s0, .o
create t-create s0, create
create t-m s0, m
create t-s s0, s,
create t-lit s0, [lit]
create t-zero s0, 0
create t-c s0, c,
create t-add s0, arc-add-object
create m1 s0, syscall.o
create m2 s0, errno.o
create m3 s0, frame.o
create m4 s0, sigreturn.o
create m5 s0, setjmp.o
create m6 s0, longjmp.o
create sysrt-list m1 , m2 , m3 , m4 , m5 , m6 , [lit] 0 ,
create newline [lit] 10 c,
create space [lit] 32 c,
variable out-fd
variable source-fd
variable wp
variable wn
variable pid
variable status
variable dfd
variable dlen
variable dpos
variable rec
variable names-here
variable scan-filter
variable scan-table
variable scan-count
variable layer-count
variable source-count
variable za
variable zb
variable sort-table
variable sort-count
variable si
variable sj
variable sv
variable pb
variable cursor
\ Keep data above the fixed VM pages, addressed through STATE, not constants.
state [lit] 4096 + here-addr !
create buffer [lit] 65536 allot
create dirbuf [lit] 32768 allot
create names-area [lit] 65536 allot
create layer-table [lit] 4096 allot
create source-table [lit] 4096 allot
create pathbuf [lit] 1024 allot
create srcbuf [lit] 1024 allot
\ ----- strings: NUL-terminated byte sequences
: zlen dup begin, dup c@ while, 1+ repeat, over - ;
: mem=
 >r zb ! za !
 begin, r@ while,
   za @ c@ zb @ c@ <> if, r> drop [lit] 0 exit, then,
   za @ 1+ za ! zb @ 1+ zb ! r> 1- >r
 repeat, r> drop [lit] 0 0= ;
: z= over zlen nip 1+ mem= ;
variable ea
variable eb
: ends? eb ! ea !
 ea @ zlen nip eb @ zlen nip
 2dup < if, 2drop [lit] 0 exit, then,
 - ea @ + eb @ eb @ zlen nip mem= ;
: z< zb ! za !
 begin, za @ c@ zb @ c@ = za @ c@ 0= 0= and while,
   za @ 1+ za ! zb @ 1+ zb !
 repeat,
 za @ c@ zb @ c@ < ;
\ ----- directory filters ( name -- flag )
: digit? [lit] 48 - [lit] 10 / 0= ;
: layer?
 dup zlen nip [lit] 11 < if, drop [lit] 0 exit, then,
 dup c@ digit? over 1+ c@ digit? and over [lit] 2 + c@ digit? and
 0= if, drop [lit] 0 exit, then,
 dup [lit] 3 + k-cc [lit] 4 mem= 0= if, drop [lit] 0 exit, then,
 dup k-fth ends? 0= if, drop [lit] 0 exit, then,
 dup k-main z= if, drop [lit] 0 exit, then,
 k-link z= 0= ;
: source?
 dup zlen nip [lit] 3 < if, drop [lit] 0 exit, then,
 dup k-dot-c ends? 0= if, drop [lit] 0 exit, then,
 k-math z= 0= ;
' layer? constant layer-xt
' source? constant source-xt
\ ----- directory listing into a table of name pointers
: copy-name
 names-here @ swap
 begin,
   dup c@ dup names-here @ c! names-here @ 1+ names-here !
 while, 1+ repeat, drop
 names-here @ names-area - [lit] 65000 < 0= if, [lit] 123 die then, ;
: table-add
 scan-count @ @ [lit] 500 < 0= if, [lit] 122 die then,
 scan-table @ scan-count @ @ [lit] 8 * + !
 scan-count @ @ 1+ scan-count @ ! ;
: scan
 [lit] 65536 [lit] 0 open dup 0< if, [lit] 120 die then, dfd !
 begin,
   dfd @ dirbuf [lit] 32768 getdents
   dup 0< if, [lit] 121 die then,
   dup
 while,
   dlen ! [lit] 0 dpos !
   begin, dpos @ dlen @ < while,
     dirbuf dpos @ + rec !
     rec @ [lit] 19 + scan-filter @ execute
     if, rec @ [lit] 19 + copy-name table-add then,
     rec @ [lit] 16 + c@ rec @ [lit] 17 + c@ [lit] 256 * + dpos @ + dpos !
   repeat,
 repeat, drop
 dfd @ checked-close ;
\ ----- insertion sort by bytes, as Python's sorted() orders these names
: slot [lit] 8 * sort-table @ + ;
: shift? sj @ 0= if, [lit] 0 exit, then, sv @ sj @ 1- slot @ z< ;
: sort
 sort-count ! sort-table ! [lit] 1 si !
 begin, si @ sort-count @ < while,
   si @ slot @ sv ! si @ sj !
   begin, shift? while,
     sj @ 1- slot @ sj @ slot ! sj @ 1- sj !
   repeat,
   sv @ sj @ slot ! si @ 1+ si !
 repeat, ;
\ ----- the seed's input file
: write-all
 wn ! wp !
 begin, wn @ while,
   out-fd @ wp @ wn @ write
   dup 0< if, [lit] 102 die then,
   dup 0= if, [lit] 103 die then,
   dup wp @ + wp ! wn @ swap - wn !
 repeat, ;
: put zlen write-all ;
: put-word put space [lit] 1 write-all ;
: nl newline [lit] 1 write-all ;
: append-file
 [lit] 0 [lit] 0 open dup 0< if, [lit] 104 die then, source-fd !
 begin,
   source-fd @ buffer [lit] 65536 read
   dup 0< if, [lit] 105 die then,
   dup
 while, buffer swap write-all repeat, drop
 source-fd @ checked-close ;
: new-input
 input-path [lit] 577 [lit] 384 open dup 0< if, [lit] 106 die then, out-fd ! ;
: end-input out-fd @ checked-close ;
: module append-file nl ;
: compiler-layers
 f010 module
 [lit] 0 cursor !
 begin, cursor @ layer-count @ < while,
   layer-table cursor @ [lit] 8 * + @ module
   cursor @ 1+ cursor !
 repeat, ;
: linker-layers f010 module f020 module f030 module f140 module f141 module ;
\ ----- run ./seed-forth on the input file; any failure stops the bootstrap
: run-seed
 fork dup 0< if, [lit] 109 die then,
 dup 0= if,
   drop
   input-path [lit] 0 [lit] 0 open dup 0< if, [lit] 110 die then,
   dup [lit] 0 dup2 0< if, [lit] 111 die then,
   close drop
   seed-path seed-argv exec drop [lit] 112 die
 then,
 pid !
 pid @ status wait4 pid @ <> if, [lit] 113 die then,
 status @ if, [lit] 114 die then, ;
\ ----- path assembly in pathbuf / srcbuf
: pb-add begin, dup c@ while, dup c@ pb @ c! pb @ 1+ pb ! 1+ repeat, drop ;
: pb-end [lit] 0 pb @ c! ;
: pb-stem
 dup zlen nip [lit] 2 -
 begin, dup while, over c@ pb @ c! pb @ 1+ pb ! 1- swap 1+ swap repeat, 2drop ;
: object-path pathbuf pb ! boot-prefix pb-add pb-stem k-dot-o pb-add pb-end ;
: member-path pathbuf pb ! boot-prefix pb-add pb-add pb-end ;
: source-path srcbuf pb ! swap pb-add pb-add pb-end ;
: mkdir-ok
 [lit] 493 mkdir dup [lit] 0 [lit] 17 - = if, drop [lit] 0 then,
 if, [lit] 107 die then, ;
\ ----- the build steps
variable unit-name
variable unit-driver
variable unit-index
: compile-unit
 unit-driver ! dup unit-name ! source-path
 new-input compiler-layers unit-driver @ append-file srcbuf append-file end-input
 run-seed
 unit-name @ object-path
 unit-object pathbuf rename if, [lit] 115 die then, ;
: make-sysrt
 new-input f010 module f020 module f030 module f081 module f122 module
 sysrt-driver append-file end-input run-seed ;
: member-line
 t-create put-word t-m put-word t-s put-word pathbuf put-word
 t-lit put-word t-zero put-word t-c put-word t-m put-word t-add put nl ;
: make-archive
 new-input linker-layers archive-head append-file
 [lit] 0 cursor !
 begin, cursor @ source-count @ < while,
   source-table cursor @ [lit] 8 * + @ object-path member-line
   cursor @ 1+ cursor !
 repeat,
 sysrt-list cursor !
 begin, cursor @ @ while,
   cursor @ @ member-path member-line
   cursor @ [lit] 8 + cursor !
 repeat,
 archive-tail append-file end-input run-seed ;
: link-program new-input linker-layers append-file end-input run-seed ;
: main
 d-build mkdir-ok d-out mkdir-ok d-boot mkdir-ok
 names-area names-here !
 layer-xt scan-filter ! layer-table scan-table ! layer-count scan-count ! d-root scan
 source-xt scan-filter ! source-table scan-table ! source-count scan-count ! d-runtime scan
 layer-table layer-count @ sort
 source-table source-count @ sort
 [lit] 0 unit-index !
 begin, unit-index @ source-count @ < while,
   runtime-prefix source-table unit-index @ [lit] 8 * + @ runtime-unit compile-unit
   unit-index @ 1+ unit-index !
 repeat,
 tools-prefix seed-cc-c tools-unit compile-unit
 tools-prefix seed-ar-c tools-unit compile-unit
 make-sysrt make-archive
 link-cc link-program link-ar link-program
 [lit] 0 die ;
main
