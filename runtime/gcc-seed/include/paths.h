#ifndef SEED_GCC_PATHS_H
#define SEED_GCC_PATHS_H
/* Explicit source policy for the supported Linux build environment. */
#define _PATH_TMP "/tmp/"
/* The one shell used by system and popen ("sh -c COMMAND"); see
   ../PROCESS-POSIX.md. Later this is the seed-built bash. */
#define _PATH_BSHELL "/bin/sh"
#define _PATH_DEVNULL "/dev/null"
#define _PATH_TTY "/dev/tty"
#endif
