#ifndef SEED_GCC_GRP_H
#define SEED_GCC_GRP_H
/* Original seed-forth interface; see LICENSE and ../PASSWD.md.
   Entries come from /etc/group only (no NSS). Results point into one
   static record that the next call of any of these functions overwrites. */
#include <sys/types.h>
struct group {
    char *gr_name;
    char *gr_passwd;
    gid_t gr_gid;
    char **gr_mem;
};
struct group *getgrnam(const char *name);
struct group *getgrgid(gid_t group);
struct group *getgrent(void);
void setgrent(void);
void endgrent(void);
/* Replace the supplementary group list (needs CAP_SETGID). */
int setgroups(size_t size, const gid_t *list);
#endif
