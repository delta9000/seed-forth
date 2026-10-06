#ifndef SEED_GCC_PWD_H
#define SEED_GCC_PWD_H
/* Original seed-forth interface; see LICENSE and ../PASSWD.md.
   Entries come from /etc/passwd only (no NSS). Results point into one
   static record that the next call of any of these functions overwrites. */
#include <sys/types.h>
struct passwd {
    char *pw_name;
    char *pw_passwd;
    uid_t pw_uid;
    gid_t pw_gid;
    char *pw_gecos;
    char *pw_dir;
    char *pw_shell;
};
struct passwd *getpwnam(const char *name);
struct passwd *getpwuid(uid_t user);
/* Sequential access; getpwent opens the file on first use. */
struct passwd *getpwent(void);
void setpwent(void);
void endpwent(void);
#endif
