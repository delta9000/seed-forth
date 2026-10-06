\ seed-cc bootstrap: the runtime archive libseed.a (loaded on 010, 020, 030,
\ 140 and 141).  tools/seed-cc-start.fth appends one arc-add-object line per
\ member, in seed-cc's order, then archive-tail.fth.
arc-init
create driver-runtime-archive s, build-out/seed-cc/boot/libseed.a [lit] 0 c,
