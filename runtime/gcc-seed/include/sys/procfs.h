#ifndef SEED_GCC_SYS_PROCFS_H
#define SEED_GCC_SYS_PROCFS_H
/* Original seed-forth declarations; see ../PROCFS.md.
   Linux AMD64 ELF core-note data records only: no functions, and no
   /proc interface. Layouts match the Linux x86-64 kernel note format. */
#include <sys/time.h>
#include <sys/types.h>

/* One saved general register; 27 make up the x86-64 register note. */
typedef unsigned long long elf_greg_t;
#define ELF_NGREG 27
typedef elf_greg_t elf_gregset_t[ELF_NGREG];

/* Signal identification at the start of the status note (12 bytes). */
struct elf_siginfo {
    int si_signo;
    int si_code;
    int si_errno;
};

/* NT_PRSTATUS descriptor: 336 bytes, register block at offset 112. */
struct elf_prstatus {
    struct elf_siginfo pr_info;
    short pr_cursig;
    unsigned long pr_sigpend;
    unsigned long pr_sighold;
    pid_t pr_pid;
    pid_t pr_ppid;
    pid_t pr_pgrp;
    pid_t pr_sid;
    struct timeval pr_utime;
    struct timeval pr_stime;
    struct timeval pr_cutime;
    struct timeval pr_cstime;
    elf_gregset_t pr_reg;
    int pr_fpvalid;
};

/* Bytes of the initial argument string kept in the process-info note. */
#define ELF_PRARGSZ 80

/* NT_PRPSINFO descriptor: 136 bytes; 32-bit user and group ids. */
struct elf_prpsinfo {
    char pr_state;
    char pr_sname;
    char pr_zomb;
    char pr_nice;
    unsigned long pr_flag;
    unsigned int pr_uid;
    unsigned int pr_gid;
    int pr_pid;
    int pr_ppid;
    int pr_pgrp;
    int pr_sid;
    char pr_fname[16];
    char pr_psargs[ELF_PRARGSZ];
};

typedef struct elf_prstatus prstatus_t;
typedef struct elf_prpsinfo prpsinfo_t;
#endif
