\ Loaded after 010-lib.fth and every numbered compiler layer except 120.
\ The following bytes in stdin are exactly tcc-sources/direct-input.c.
\ Forth performs all preprocessing and emits the complete static ELF.
true cc-target-lp64 !
true cc-prep-direct !
[lit] 1 cc-bootstrap-floatbits !
[lit] 8388608 cc-arena-map
create tcc-output s, build-out/tcc-seed.partial [lit] 0 c,
create tcc-source s, build-out/tcc-sources/direct-input.c
tcc-source [lit] 36 cc-prep-source-name
create tcc-include s, build-out/tcc-sources/libc64/include
tcc-include [lit] 36 cc-prep-add-include
variable tcc-fd
variable tcc-pointer
variable tcc-count
\ Unlike the legacy single-write helper, check every write and the close.
: tcc-write-output
  tcc-output [lit] 577 [lit] 384 open
  dup 0< if, [lit] 121 die then, tcc-fd !
  cc-out-buf tcc-pointer ! cc-out-pos @ tcc-count !
  begin, tcc-count @ while,
    tcc-fd @ tcc-pointer @ tcc-count @ write
    dup 0< if, [lit] 122 die then,
    dup 0= if, [lit] 123 die then,
    dup tcc-pointer +! tcc-count @ swap - tcc-count !
  repeat,
  tcc-fd @ close if, [lit] 124 die then, ;
: tcc-main
  cc-load-stdin cc-preprocess cc-out-init cc-globals-init
  cc-emit-elf-header cc-native-program cc-finalize-globals cc-finalize-elf
  tcc-write-output bye ;
tcc-main
