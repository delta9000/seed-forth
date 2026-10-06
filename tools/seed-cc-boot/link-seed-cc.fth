\ seed-cc bootstrap: link seed-cc as seed-cc links a program: startup first,
\ then the program object, then the lazily searched runtime archive.
lnk-init
create driver-obj-0 s, build-out/seed-cc/boot/start.o [lit] 0 c,
driver-obj-0 lnk-add-object
create driver-obj-1 s, build-out/seed-cc/boot/seed-cc.o [lit] 0 c,
driver-obj-1 lnk-add-object
create driver-obj-2 s, build-out/seed-cc/boot/libseed.a [lit] 0 c,
driver-obj-2 lnk-add-archive
create driver-entry s, _start
driver-entry [lit] 6 lnk-entry
create driver-output s, build-out/seed-cc/seed-cc [lit] 0 c,
driver-output lnk-link bye
