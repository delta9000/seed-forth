/* Includes the unchanged binutils 2.30 bfd/hosts/x86-64linux.h the way
   bfd/elf.c does (after ansidecl.h, with HAVE_STDINT_H from bfd configure)
   and prints the core-note record layouts elf64-x86-64.c depends on. The
   Forth build must match host GCC with host glibc headers byte for byte. */
#define HAVE_STDINT_H 1
#include "ansidecl.h"
#include <stddef.h>
#include <stdio.h>
#include "hosts/x86-64linux.h"

#define SIZE(t) printf("%s size=%ld\n", #t, (long)sizeof(t))
#define AT(t, m) printf("%s.%s offset=%ld\n", #t, #m, (long)offsetof(t, m))

int main(void)
{
    SIZE(prstatus_t); SIZE(prpsinfo_t); SIZE(struct elf_siginfo);
    SIZE(prstatus32_t); SIZE(prstatusx32_t); SIZE(prstatus64_t);
    SIZE(prpsinfo32_t); SIZE(prpsinfo64_t);
    SIZE(elf_gregset32_t); SIZE(elf_gregset64_t);
    AT(prstatus_t, pr_reg); AT(prstatus32_t, pr_reg); AT(prstatusx32_t, pr_reg);
    AT(prstatus64_t, pr_reg); AT(prstatus64_t, pr_pid); AT(prstatus64_t, pr_cursig);
    AT(prstatus64_t, pr_fpvalid); AT(prstatus32_t, pr_pid); AT(prstatus32_t, pr_fpvalid);
    AT(prpsinfo32_t, pr_pid); AT(prpsinfo32_t, pr_fname); AT(prpsinfo32_t, pr_psargs);
    AT(prpsinfo64_t, pr_pid); AT(prpsinfo64_t, pr_fname); AT(prpsinfo64_t, pr_psargs);
    AT(prpsinfo_t, pr_pid); AT(prpsinfo_t, pr_fname); AT(prpsinfo_t, pr_psargs);
    return 0;
}
