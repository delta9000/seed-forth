#ifndef SEED_GCC_SYS_UTSNAME_H
#define SEED_GCC_SYS_UTSNAME_H
/* Original seed-forth interface; see LICENSE and ../../SYSINFO.md.
   The Linux new_utsname record: six 65-byte NUL-terminated fields. */
#define _UTSNAME_LENGTH 65
struct utsname {
    char sysname[_UTSNAME_LENGTH];
    char nodename[_UTSNAME_LENGTH];
    char release[_UTSNAME_LENGTH];
    char version[_UTSNAME_LENGTH];
    char machine[_UTSNAME_LENGTH];
    char domainname[_UTSNAME_LENGTH];
};
int uname(struct utsname *name);
#endif
