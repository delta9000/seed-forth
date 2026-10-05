#ifndef SEED_GCC_LOCALE_H
#define SEED_GCC_LOCALE_H
/* Fixed C/POSIX locale support; other requested locales fail unchanged. */
#define LC_CTYPE 0
#define LC_NUMERIC 1
#define LC_TIME 2
#define LC_COLLATE 3
#define LC_MONETARY 4
#define LC_MESSAGES 5
#define LC_ALL 6
char *setlocale(int category, const char *locale);
#endif
