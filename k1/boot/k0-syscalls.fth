\ K0 has no stat, fstat, munmap or getpid: it answers them ENOSYS (-38).
\ The object writer (081) and the linker (140) use them only to check their
\ files and to name temporaries, so under K0 this syscall6, loaded right
\ after 010-lib.fth and before the layers that call it, retries a call that
\ returned ENOSYS with what K0 can do.  On Linux no call returns ENOSYS and
\ nothing changes.  The fallbacks:
\   stat   -> lstat into a zeroed buffer (K0 fills st_mode only; there are
\             no symlinks), device -2, so it matches no input
\   fstat  -> a zeroed buffer with device -1 and a new inode number per call,
\             so inputs stay distinct (K0 has no hard links)
\   munmap -> 0 (the memory is not returned)
\   getpid -> 1 (K0 runs one process at a time)
' syscall6 constant k0-seed-syscall6
variable k0-a variable k0-b variable k0-c variable k0-d variable k0-e
variable k0-f variable k0-n variable k0-inode
: k0-zero-stat ( buffer -- )
  [lit] 0 begin, dup [lit] 144 < while,
    over over + [lit] 0 swap c! 1+
  repeat, 2drop ;
: syscall6 ( a b c d e f n -- result )
  k0-n ! k0-f ! k0-e ! k0-d ! k0-c ! k0-b ! k0-a !
  k0-a @ k0-b @ k0-c @ k0-d @ k0-e @ k0-f @ k0-n @ k0-seed-syscall6 execute
  dup [lit] 0 [lit] 38 - <> if, exit, then,
  k0-n @ [lit] 4 = if, drop
    k0-b @ k0-zero-stat
    k0-a @ k0-b @ [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 6 k0-seed-syscall6 execute
    dup 0= if, [lit] 0 [lit] 2 - k0-b @ ! then, exit,
  then,
  k0-n @ [lit] 5 = if, drop
    k0-b @ k0-zero-stat true k0-b @ !
    [lit] 1 k0-inode +! k0-inode @ k0-b @ [lit] 8 + !
    [lit] 0 exit,
  then,
  k0-n @ [lit] 11 = if, drop [lit] 0 exit, then,
  k0-n @ [lit] 39 = if, drop [lit] 1 exit, then, ;
