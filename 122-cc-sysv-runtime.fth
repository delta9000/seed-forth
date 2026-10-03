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
