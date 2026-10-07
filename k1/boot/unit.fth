\ Compile one K1 C file (on stdin after this text) to
\ build-out/k1-direct/unit.o, as seed-cc -nostdinc -c does: the same driver
\ words and arena, no include directories.  Quoted includes resolve from k1/;
\ the recipe renames the object.
cc-sysv-object-enable
[lit] 22020096 cc-arena-map
cc-io-direct-workspace cc-prep-direct-workspace
cc-om-direct-workspace cc-label-direct-workspace
cc-obj-direct-workspace cc-gfixup-direct-workspace
create driver-output s, build-out/k1-direct/unit.o [lit] 0 c,
create driver-source s, k1/unit.c [lit] 0 c,
driver-source [lit] 9 cc-prep-source-name
: driver-main cc-load-stdin cc-preprocess cc-out-init cc-globals-init
cc-sysv-object-program driver-output cc-obj-write bye ;
driver-main
