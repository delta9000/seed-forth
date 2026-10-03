#ifndef SEED_GCC_CTYPE_H
#define SEED_GCC_CTYPE_H
/* Original seed-forth interface; see LICENSE. Fixed ASCII C locale.
   The supported argument domain is EOF (-1) or an unsigned-char value.
   These seven functions are the surface used by original oyacc 6.6. */
int isalpha(int value);
int isalnum(int value);
int isdigit(int value);
int isprint(int value);
int isspace(int value);
int isupper(int value);
int tolower(int value);
#endif
