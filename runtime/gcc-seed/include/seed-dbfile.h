#ifndef SEED_GCC_DBFILE_H
#define SEED_GCC_DBFILE_H
/* Private helpers for /etc/passwd and /etc/group; see ../PASSWD.md. */
/* The whole file in a malloc'd NUL-terminated buffer, or NULL with errno. */
char *__seed_load_file(const char *path);
/* The next line at *CURSOR without leading blanks, NUL-terminated in place;
   NULL at the end. Empty lines and lines starting with '#' or '+' (NIS
   compatibility markers, unsupported) are skipped. */
char *__seed_next_entry(char **cursor);
/* Split LINE in place at ':' into exactly COUNT fields (the last keeps any
   further colons); returns 0, leaving LINE unchanged, if there are fewer. */
int __seed_split_fields(char *line, char **fields, int count);
/* A decimal ID of 1..10 digits below 2^32; returns 0 if malformed. */
int __seed_parse_id(const char *text, unsigned int *value);
#endif
