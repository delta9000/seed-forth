/* Prints <sys/procfs.h> and <sys/time.h> layout facts. The Forth build
   (runtime headers) must match host GCC with host glibc headers byte for
   byte. Host GCC also compiles this file against the runtime headers alone,
   where the pointer initializers prove exact type identity. */
#include <features.h>
#include <sys/time.h>
#include <sys/procfs.h>
#include <sys/types.h>
#include <stddef.h>
#include <stdio.h>

#define SIZE(t) show(#t, "size", (long)sizeof(t))
#define AT(t, m) show(#t "." #m, "offset", (long)offsetof(t, m))
#define MEMBER(t, m) { t probe; AT(t, m); show(#t "." #m, "size", (long)sizeof(probe.m)); }
#define ALIGN(n) show(#n, "align", (long)offsetof(struct n, value))
#define SAME(t, u) { t *pointer = (u *)0; if (pointer) return 99; }

#if ELF_PRARGSZ != 80
#error the argument-string size must be usable in #if
#endif

struct align_greg { char pad; elf_greg_t value; };
struct align_gregset { char pad; elf_gregset_t value; };
struct align_siginfo { char pad; struct elf_siginfo value; };
struct align_prstatus { char pad; prstatus_t value; };
struct align_prpsinfo { char pad; prpsinfo_t value; };
struct align_timeval { char pad; struct timeval value; };
struct align_suseconds { char pad; suseconds_t value; };

static void show(const char *name, const char *kind, long value)
{
    printf("%s %s=%ld\n", name, kind, value);
}

int main(void)
{
    prstatus_t status;
    prpsinfo_t info;
    SAME(elf_greg_t, unsigned long long) SAME(suseconds_t, long) SAME(time_t, long)
    SAME(pid_t, int) SAME(prstatus_t, struct elf_prstatus) SAME(prpsinfo_t, struct elf_prpsinfo)
    { short *p = &status.pr_cursig; unsigned long *q = &status.pr_sigpend;
      pid_t *r = &status.pr_sid; struct timeval *s = &status.pr_cstime;
      int *t = &status.pr_fpvalid; struct elf_siginfo *u = &status.pr_info;
      elf_greg_t *v = status.pr_reg;
      if (p == 0 || q == 0 || r == 0 || s == 0 || t == 0 || u == 0 || v == 0) return 98; }
    { unsigned long *p = &info.pr_flag; unsigned int *q = &info.pr_gid; int *r = &info.pr_sid;
      char *s = info.pr_psargs; char *t = &info.pr_nice;
      if (p == 0 || q == 0 || r == 0 || s == 0 || t == 0) return 97; }
    { int (*clock_reader)(struct timeval *, void *) = gettimeofday;
      if (clock_reader == 0) return 96; }
    show("ELF_NGREG", "value", (long)ELF_NGREG);
    show("ELF_PRARGSZ", "value", (long)ELF_PRARGSZ);
    show("elf_greg_t", "unsigned", (long)((elf_greg_t)-1 > 0));
    SIZE(elf_greg_t); SIZE(elf_gregset_t); SIZE(struct elf_siginfo);
    SIZE(prstatus_t); SIZE(prpsinfo_t); SIZE(struct timeval); SIZE(suseconds_t);
    SIZE(time_t); SIZE(pid_t);
    ALIGN(align_greg); ALIGN(align_gregset); ALIGN(align_siginfo); ALIGN(align_prstatus);
    ALIGN(align_prpsinfo); ALIGN(align_timeval); ALIGN(align_suseconds);
    MEMBER(struct elf_siginfo, si_signo) MEMBER(struct elf_siginfo, si_code)
    MEMBER(struct elf_siginfo, si_errno)
    MEMBER(struct timeval, tv_sec) MEMBER(struct timeval, tv_usec)
    MEMBER(prstatus_t, pr_info) MEMBER(prstatus_t, pr_cursig) MEMBER(prstatus_t, pr_sigpend)
    MEMBER(prstatus_t, pr_sighold) MEMBER(prstatus_t, pr_pid) MEMBER(prstatus_t, pr_ppid)
    MEMBER(prstatus_t, pr_pgrp) MEMBER(prstatus_t, pr_sid) MEMBER(prstatus_t, pr_utime)
    MEMBER(prstatus_t, pr_stime) MEMBER(prstatus_t, pr_cutime) MEMBER(prstatus_t, pr_cstime)
    MEMBER(prstatus_t, pr_reg) MEMBER(prstatus_t, pr_fpvalid)
    MEMBER(prpsinfo_t, pr_state) MEMBER(prpsinfo_t, pr_sname) MEMBER(prpsinfo_t, pr_zomb)
    MEMBER(prpsinfo_t, pr_nice) MEMBER(prpsinfo_t, pr_flag) MEMBER(prpsinfo_t, pr_uid)
    MEMBER(prpsinfo_t, pr_gid) MEMBER(prpsinfo_t, pr_pid) MEMBER(prpsinfo_t, pr_ppid)
    MEMBER(prpsinfo_t, pr_pgrp) MEMBER(prpsinfo_t, pr_sid) MEMBER(prpsinfo_t, pr_fname)
    MEMBER(prpsinfo_t, pr_psargs)
    /* Signedness of the scalar members (1 = unsigned). */
    status.pr_cursig = -1; status.pr_sigpend = 0; status.pr_sigpend -= 1;
    info.pr_uid = 0; info.pr_uid -= 1; info.pr_pid = -1; info.pr_state = -1;
    show("prstatus_t.pr_cursig", "unsigned", (long)(status.pr_cursig > 0));
    show("prstatus_t.pr_sigpend", "unsigned", (long)(status.pr_sigpend > 0));
    show("prpsinfo_t.pr_uid", "unsigned", (long)(info.pr_uid > 0));
    show("prpsinfo_t.pr_pid", "unsigned", (long)(info.pr_pid > 0));
    show("prpsinfo_t.pr_state", "unsigned", (long)(info.pr_state > 0));
    return 0;
}
