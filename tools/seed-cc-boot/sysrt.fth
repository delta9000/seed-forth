\ seed-cc bootstrap: the seven Forth-generated runtime objects, written as
\ tools/seed-cc.c writes them (loaded on 010, 020, 030, 081 and 122).
create syscall-path s, build-out/seed-cc/boot/syscall.o [lit] 0 c,
cc-sysrt-object syscall-path cc-obj-write
create errno-path s, build-out/seed-cc/boot/errno.o [lit] 0 c,
cc-sysrt-errno-object errno-path cc-obj-write
create start-path s, build-out/seed-cc/boot/start.o [lit] 0 c,
cc-sysrt-runtime-start-object start-path cc-obj-write
create frame-path s, build-out/seed-cc/boot/frame.o [lit] 0 c,
cc-sysrt-frame-object frame-path cc-obj-write
create sigreturn-path s, build-out/seed-cc/boot/sigreturn.o [lit] 0 c,
cc-sysrt-sigreturn-object sigreturn-path cc-obj-write
create setjmp-path s, build-out/seed-cc/boot/setjmp.o [lit] 0 c,
cc-sysrt-setjmp-object setjmp-path cc-obj-write
create longjmp-path s, build-out/seed-cc/boot/longjmp.o [lit] 0 c,
cc-sysrt-longjmp-object longjmp-path cc-obj-write
bye
