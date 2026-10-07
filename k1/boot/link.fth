\ Link K1 at 0x200000 (loaded on 010, 020, 030 and 140): the assembly object
\ first, as k1/build.sh orders k1.S, then the C objects; entry _start.
[lit] 2097152 lnk-base-address !
lnk-init
create k1-obj-0 s, build-out/k1-direct/k1-asm.o [lit] 0 c,
k1-obj-0 lnk-add-object
create k1-obj-1 s, build-out/k1-direct/main.o [lit] 0 c,
k1-obj-1 lnk-add-object
create k1-obj-2 s, build-out/k1-direct/mm.o [lit] 0 c,
k1-obj-2 lnk-add-object
create k1-obj-3 s, build-out/k1-direct/fs.o [lit] 0 c,
k1-obj-3 lnk-add-object
create k1-obj-4 s, build-out/k1-direct/proc.o [lit] 0 c,
k1-obj-4 lnk-add-object
create k1-obj-5 s, build-out/k1-direct/sys.o [lit] 0 c,
k1-obj-5 lnk-add-object
create k1-obj-6 s, build-out/k1-direct/linux.o [lit] 0 c,
k1-obj-6 lnk-add-object
create k1-obj-7 s, build-out/k1-direct/ata.o [lit] 0 c,
k1-obj-7 lnk-add-object
create k1-entry s, _start
k1-entry [lit] 6 lnk-entry
create k1-output s, build-out/k1-direct/k1 [lit] 0 c,
k1-output lnk-link bye
