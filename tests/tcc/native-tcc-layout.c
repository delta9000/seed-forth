#include "tcc.h"
int main(void) {
    if (sizeof(Elf64_Ehdr) != 64) return 1;
    if (sizeof(Elf64_Phdr) != 56) return 2;
    if (sizeof(Elf64_Shdr) != 64) return 3;
    if (sizeof(Elf64_Sym) != 24) return 4;
    if (sizeof(Elf64_Rela) != 24) return 5;
    if (sizeof(Elf64_Dyn) != 16) return 6;
    TCCState s;
    Sym a;
    s.warn_unsupported = 23;
    s.nostdlib = 42;
    a.c = 17;
    a.sym_scope = 29;
    a.type.t = 41;
    if (s.warn_unsupported != 23 || s.nostdlib != 42) return 7;
    if (a.c != 17 || a.sym_scope != 29 || a.type.t != 41) return 8;
    return 0;
}
