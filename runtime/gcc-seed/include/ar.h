#ifndef SEED_GCC_AR_H
#define SEED_GCC_AR_H
/* Original seed-forth interface; see LICENSE and ../FILE-CALLS.md.
   The common ar archive member header: 60 bytes of space-padded text. */
#define ARMAG "!<arch>\n"
#define SARMAG 8
#define ARFMAG "`\n"
struct ar_hdr {
    char ar_name[16];
    char ar_date[12];
    char ar_uid[6];
    char ar_gid[6];
    char ar_mode[8];
    char ar_size[10];
    char ar_fmag[2];
};
#endif
