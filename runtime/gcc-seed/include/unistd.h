#ifndef SEED_GCC_UNISTD_H
#define SEED_GCC_UNISTD_H
/* Original seed-forth bounded interface; only implemented calls appear here. */
extern char *optarg;
extern int optind;
extern int opterr;
extern int optopt;
/* POSIX-style short options; stops at the first operand, no permutation. */
int getopt(int count, char *const arguments[], const char *options);
int unlink(const char *path);
void _exit(int status);
#endif
