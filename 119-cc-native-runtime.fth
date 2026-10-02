\ 119-cc-native-runtime.fth — Linux AMD64 primitives for the native ABI.
\ Every argument occupies an eight-byte caller-owned stack slot. These
\ leaf functions have no frame: argument one is at rsp+8, not in rdi.
\ Portable libc supplies FILE, allocation, strings, stdio and formatting.
\ Only its kernel boundary is emitted here; no SysV libc shim is linked.

create cc-native-name-exit     s, exit
create cc-native-name-read     s, read
create cc-native-name-write    s, write
create cc-native-name-open     s, open
create cc-native-name-close    s, close
create cc-native-name-lseek    s, lseek
create cc-native-name-unlink   s, unlink
create cc-native-name-mkdir    s, mkdir
create cc-native-name-chmod    s, chmod
create cc-native-name-access   s, access
create cc-native-name-mprotect s, mprotect
create cc-native-name-time     s, time
create cc-native-name-gettimeofday s, gettimeofday

\ cc-native-sysarg ( stack-byte-offset modrm -- )
\ MOV a full stack cell into a syscall argument register. Narrow C values
\ arrive extended by expression evaluation; pointers/size_t/off_t stay 64-bit.
: cc-native-sysarg
  [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte
  cc-emit-byte [lit] 36 cc-emit-byte cc-emit-byte ;

\ cc-native-syscall ( syscall-number argument-count -- )
\ Linux returns -errno in rax. Portable libc tests fd == -1, so turn
\ [-4095,-1] into -1. This bootstrap boundary does not maintain errno.
\ Unlike the old pnut boundary, an absent file therefore makes fopen fail
\ cleanly rather than allocating a FILE containing a negative errno.
: cc-native-syscall
  dup [lit] 0 > if, [lit] 8 [lit] 124 cc-native-sysarg then,
  dup [lit] 1 > if, [lit] 16 [lit] 116 cc-native-sysarg then,
  [lit] 2 > if, [lit] 24 [lit] 84 cc-native-sysarg then,
  [lit] 184 cc-emit-byte cc-emit-4le             \ mov eax, syscall-number
  [lit] 15 cc-emit-byte [lit] 5 cc-emit-byte     \ syscall
  [lit] 72 cc-emit-byte [lit] 61 cc-emit-byte
  [lit] 0 [lit] 4095 - cc-emit-4le              \ cmp rax, -4095
  [lit] 114 cc-emit-byte [lit] 7 cc-emit-byte    \ jb .ok (unsigned)
  [lit] 72 cc-emit-byte [lit] 199 cc-emit-byte [lit] 192 cc-emit-byte
  [lit] 0 1- cc-emit-4le                        \ mov rax, -1
  [lit] 195 cc-emit-byte ;                      \ .ok: ret

\ cc-native-primitive ( name-addr name-len return-base syscall argc -- )
\ Register the real return type before parsing source prototypes. In
\ particular read/write/lseek return signed LP64 long, never 32-bit int.
: cc-native-primitive
  >r >r [lit] 0 ty-make sk-func swap cc-here-vaddr cc-sym-add drop
  r> r> cc-native-syscall ;

\ These three unavailable library paths are part of the measured seed-only
\ profile. Do not generalize this allow-list to arbitrary unresolved names.
\ Successful bootstrap builds must never execute one: each names the missing
\ operation on stderr and exits 125. Normal native mode does not define them.
create cc-native-name-localtime s, localtime
create cc-native-name-ldexp     s, ldexp
create cc-native-name-longjmp   s, longjmp
create cc-native-trap-prefix
  s, seed-forth [lit] 32 c, s, bootstrap: [lit] 32 c,
  s, unsupported [lit] 32 c,
here cc-native-trap-prefix - constant cc-native-trap-prefix-length
variable cc-native-trap-message
variable cc-native-trap-length

: cc-native-emit-raw ( addr len -- )
  begin, dup while,
    over c@ cc-emit-byte swap 1+ swap 1-
  repeat, 2drop ;

: cc-native-unavailable ( name-addr name-len return-type -- )
  >r 2dup
  cc-here-vaddr cc-native-trap-message !
  cc-native-trap-prefix cc-native-trap-prefix-length cc-native-emit-raw
  cc-native-emit-raw [lit] 10 cc-emit-byte
  dup cc-native-trap-prefix-length 1+ + cc-native-trap-length !
  sk-func r> cc-here-vaddr cc-sym-add drop
  [lit] 184 cc-emit-byte [lit] 1 cc-emit-4le       \ mov eax, SYS_write
  [lit] 191 cc-emit-byte [lit] 2 cc-emit-4le       \ mov edi, stderr
  [lit] 72 cc-emit-byte [lit] 190 cc-emit-byte
  cc-native-trap-message @ cc-emit-8le            \ movabs rsi, message
  [lit] 186 cc-emit-byte cc-native-trap-length @ cc-emit-4le
  [lit] 15 cc-emit-byte [lit] 5 cc-emit-byte       \ syscall
  [lit] 184 cc-emit-byte [lit] 60 cc-emit-4le      \ mov eax, SYS_exit
  [lit] 191 cc-emit-byte [lit] 125 cc-emit-4le     \ mov edi, 125
  [lit] 15 cc-emit-byte [lit] 5 cc-emit-byte
  [lit] 15 cc-emit-byte [lit] 11 cc-emit-byte ;    \ ud2: never return

: cc-native-runtime
  cc-native-name-exit     [lit] 4 ty-void [lit] 60 [lit] 1 cc-native-primitive
  cc-native-name-read     [lit] 4 ty-long [lit] 0 [lit] 3 cc-native-primitive
  cc-native-name-write    [lit] 5 ty-long [lit] 1 [lit] 3 cc-native-primitive
  \ open's third stack slot contains mode for O_CREAT/O_TMPFILE. Linux
  \ ignores that slot for a two-argument open without those flags.
  cc-native-name-open     [lit] 4 ty-int [lit] 2 [lit] 3 cc-native-primitive
  cc-native-name-close    [lit] 5 ty-int [lit] 3 [lit] 1 cc-native-primitive
  cc-native-name-lseek    [lit] 5 ty-long [lit] 8 [lit] 3 cc-native-primitive
  cc-native-name-unlink   [lit] 6 ty-int [lit] 87 [lit] 1 cc-native-primitive
  cc-native-name-mkdir    [lit] 5 ty-int [lit] 83 [lit] 2 cc-native-primitive
  cc-native-name-chmod    [lit] 5 ty-int [lit] 90 [lit] 2 cc-native-primitive
  cc-native-name-access   [lit] 6 ty-int [lit] 21 [lit] 2 cc-native-primitive
  cc-native-name-mprotect [lit] 8 ty-int [lit] 10 [lit] 3 cc-native-primitive
  cc-native-name-time     [lit] 4 ty-long [lit] 201 [lit] 1 cc-native-primitive
  cc-native-name-gettimeofday [lit] 12 ty-int [lit] 96 [lit] 2 cc-native-primitive
  cc-bootstrap-floatbits @ if,
    cc-native-name-localtime [lit] 9 ty-struct [lit] 1 ty-make cc-native-unavailable
    cc-native-name-ldexp [lit] 5 ty-double [lit] 0 ty-make cc-native-unavailable
    cc-native-name-longjmp [lit] 7 ty-void [lit] 0 ty-make cc-native-unavailable
  then, ;
' cc-native-runtime is cc-native-runtime-fwd
