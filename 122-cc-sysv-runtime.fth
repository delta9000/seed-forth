\ 122-cc-sysv-runtime.fth -- raw Linux syscall bridge for a source-built runtime.
\ Load after 010, 020, 030, and 081. Loading this file emits no target code.
\ cc-sysrt-object creates one ET_REL object; cc-obj-write saves it.
\
\ C signature: long __seed_syscall6(long number, long a1, long a2, long a3,
\                                long a4, long a5, long a6);
\ Return the raw kernel result. Values -4095..-1 are errors; no errno is set.
\ The caller, not this leaf, converts that result to its public libc contract.

create cc-sysrt-name  s, __seed_syscall6
create cc-sysrt-code
[lit] 72 c, [lit] 137 c, [lit] 248 c,  \ mov rax,rdi       syscall number
[lit] 72 c, [lit] 137 c, [lit] 247 c,  \ mov rdi,rsi       argument 1
[lit] 72 c, [lit] 137 c, [lit] 214 c,  \ mov rsi,rdx       argument 2
[lit] 72 c, [lit] 137 c, [lit] 202 c,  \ mov rdx,rcx       argument 3
[lit] 77 c, [lit] 137 c, [lit] 194 c,  \ mov r10,r8        argument 4
[lit] 77 c, [lit] 137 c, [lit] 200 c,  \ mov r8,r9         argument 5
[lit] 76 c, [lit] 139 c, [lit] 76 c, [lit] 36 c, [lit] 8 c,
                                      \ mov r9,[rsp+8]    argument 6
[lit] 15 c, [lit] 5 c,                \ syscall           clobbers rcx,r11
[lit] 195 c,                          \ ret               result in rax

: cc-sysrt-object
  cc-obj-init
  cc-obj-text cc-obj-use
  cc-sysrt-code [lit] 26 cc-obj-bytes
  cc-sysrt-name [lit] 15 [lit] 1 [lit] 2 [lit] 0
  cc-obj-text [lit] 0 [lit] 26 cc-obj-symbol drop ;

\ A separate object owns errno for this explicitly single-threaded runtime.
\ Keep it separate so the raw bridge has no libc state or provider collision.
create cc-sysrt-errno-name  s, __errno_location
create cc-sysrt-errno-storage  s, __seed_errno
create cc-sysrt-errno-code
[lit] 72 c, [lit] 141 c, [lit] 5 c,   \ lea rax,[rip+errno]
[lit] 0 c, [lit] 0 c, [lit] 0 c, [lit] 0 c,
[lit] 195 c,                         \ ret

: cc-sysrt-errno-object
  cc-obj-init
  cc-obj-bss cc-obj-use [lit] 4 cc-obj-align [lit] 4 cc-obj-reserve drop
  cc-sysrt-errno-storage [lit] 12 cc-obj-local cc-obj-object cc-obj-default
  cc-obj-bss [lit] 0 [lit] 4 cc-obj-symbol >r
  cc-obj-text cc-obj-use cc-sysrt-errno-code [lit] 8 cc-obj-bytes
  cc-obj-text [lit] 3 cc-obj-pc32 r> [lit] 0 [lit] 4 - cc-obj-reloc
  cc-sysrt-errno-name [lit] 16 cc-obj-global cc-obj-func cc-obj-default
  cc-obj-text [lit] 0 [lit] 8 cc-obj-symbol drop ;

\ Process entry: preserve argc and argv before aligning the outgoing call.
\ Relocate the call to C main, then pass its return value to Linux exit.
create cc-sysrt-main-name  s, main
create cc-sysrt-start-name  s, _start
create cc-sysrt-start-code
[lit] 72 c, [lit] 139 c, [lit] 60 c, [lit] 36 c, \ mov rdi,[rsp]
[lit] 72 c, [lit] 141 c, [lit] 116 c, [lit] 36 c, [lit] 8 c,
                                                 \ lea rsi,[rsp+8]
[lit] 72 c, [lit] 131 c, [lit] 228 c, [lit] 240 c, \ and rsp,-16
[lit] 49 c, [lit] 192 c,                         \ xor eax,eax
[lit] 232 c, [lit] 0 c, [lit] 0 c, [lit] 0 c, [lit] 0 c,
                                                 \ call main (RELA at16)
[lit] 72 c, [lit] 137 c, [lit] 199 c,             \ mov rdi,rax
[lit] 184 c, [lit] 60 c, [lit] 0 c, [lit] 0 c, [lit] 0 c,
                                                 \ mov eax,60
[lit] 15 c, [lit] 5 c,                           \ syscall
[lit] 15 c, [lit] 11 c,                          \ ud2 if exit returned

: cc-sysrt-start-object
  cc-obj-init
  cc-sysrt-main-name [lit] 4 cc-obj-global cc-obj-func cc-obj-default
  cc-obj-undef [lit] 0 [lit] 0 cc-obj-symbol >r
  cc-obj-text cc-obj-use cc-sysrt-start-code [lit] 32 cc-obj-bytes
  cc-obj-text [lit] 16 cc-obj-plt32 r> [lit] 0 [lit] 4 - cc-obj-reloc
  cc-sysrt-start-name [lit] 6 cc-obj-global cc-obj-func cc-obj-default
  cc-obj-text [lit] 0 [lit] 32 cc-obj-symbol drop ;
