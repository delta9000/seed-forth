\ Separate producer/consumer objects, emitted by 081 and linked by 140.
\ The driver defines linker-a-path, linker-b-path and linker-out-path.
create linker-start-name s, _start
create linker-compute-name s, compute
create linker-value-name s, answer
create linker-pointer-name s, pointer
create linker-zero-name s, zero
variable linker-compute-id
variable linker-value-id
variable linker-pointer-id
variable linker-zero-id

cc-obj-init
cc-obj-text cc-obj-use
[lit] 232 cc-obj-byte [lit] 0 cc-obj-4le
[lit] 137 cc-obj-byte [lit] 199 cc-obj-byte
[lit] 184 cc-obj-byte [lit] 60 cc-obj-4le
[lit] 15 cc-obj-byte [lit] 5 cc-obj-byte
linker-start-name [lit] 6 cc-obj-global cc-obj-func cc-obj-default
cc-obj-text [lit] 0 [lit] 14 cc-obj-symbol drop
linker-compute-name [lit] 7 cc-obj-global cc-obj-func cc-obj-default
cc-obj-undef [lit] 0 [lit] 0 cc-obj-symbol linker-compute-id !
linker-value-name [lit] 6 cc-obj-global cc-obj-object cc-obj-default
cc-obj-undef [lit] 0 [lit] 0 cc-obj-symbol linker-value-id !
cc-obj-data cc-obj-use [lit] 32 cc-obj-align [lit] 0 cc-obj-8le
linker-pointer-name [lit] 7 cc-obj-global cc-obj-object cc-obj-default
cc-obj-data [lit] 0 [lit] 8 cc-obj-symbol drop
cc-obj-text [lit] 1 cc-obj-plt32 linker-compute-id @ [lit] 0 [lit] 4 - cc-obj-reloc
cc-obj-data [lit] 0 cc-obj-r64 linker-value-id @ [lit] 0 cc-obj-reloc
linker-a-path cc-obj-write

cc-obj-init
cc-obj-text cc-obj-use [lit] 64 cc-obj-align
[lit] 72 cc-obj-byte [lit] 139 cc-obj-byte [lit] 5 cc-obj-byte [lit] 0 cc-obj-4le
[lit] 139 cc-obj-byte [lit] 0 cc-obj-byte
[lit] 3 cc-obj-byte [lit] 5 cc-obj-byte [lit] 0 cc-obj-4le
[lit] 195 cc-obj-byte
linker-compute-name [lit] 7 cc-obj-global cc-obj-func cc-obj-default
cc-obj-text [lit] 0 [lit] 16 cc-obj-symbol drop
linker-pointer-name [lit] 7 cc-obj-global cc-obj-object cc-obj-default
cc-obj-undef [lit] 0 [lit] 0 cc-obj-symbol linker-pointer-id !
cc-obj-data cc-obj-use [lit] 16 cc-obj-align [lit] 42 cc-obj-4le
linker-value-name [lit] 6 cc-obj-global cc-obj-object cc-obj-default
cc-obj-data [lit] 0 [lit] 4 cc-obj-symbol drop
cc-obj-bss cc-obj-use [lit] 8192 cc-obj-reserve drop
linker-zero-name [lit] 4 cc-obj-global cc-obj-object cc-obj-default
cc-obj-bss [lit] 4096 [lit] 4 cc-obj-symbol linker-zero-id !
cc-obj-text [lit] 3 cc-obj-pc32 linker-pointer-id @ [lit] 0 [lit] 4 - cc-obj-reloc
cc-obj-text [lit] 11 cc-obj-pc32 linker-zero-id @ [lit] 0 [lit] 4 - cc-obj-reloc
linker-b-path cc-obj-write

lnk-init
linker-a-path lnk-add-object
linker-b-path lnk-add-object
linker-start-name [lit] 6 lnk-entry
linker-out-path lnk-link
