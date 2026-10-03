#ifndef SEED_GCC_STDIO_H
#define SEED_GCC_STDIO_H
/* Original seed-forth interface; see LICENSE. Linux AMD64, single-threaded.
   FILE is opaque and unbuffered. There is no host-libc FILE compatibility.
   Formatting supports integer, pointer, narrow string/character, and %n;
   floating, wide, positional, and locale conversions fail with EINVAL. */
#include <stddef.h>
#include <stdarg.h>
typedef struct __seed_FILE FILE;
#define EOF (-1)
FILE *__seed_stdin(void);
FILE *__seed_stdout(void);
FILE *__seed_stderr(void);
#define stdin (__seed_stdin())
#define stdout (__seed_stdout())
#define stderr (__seed_stderr())
FILE *fopen(const char *path, const char *mode);
int fclose(FILE *stream);
int fflush(FILE *stream);
int ferror(FILE *stream);
int feof(FILE *stream);
void clearerr(FILE *stream);
size_t fwrite(const void *data, size_t size, size_t count, FILE *stream);
size_t fread(void *data, size_t size, size_t count, FILE *stream);
int fputc(int byte, FILE *stream);
int putc(int byte, FILE *stream);
int putchar(int byte);
int fputs(const char *text, FILE *stream);
int puts(const char *text);
int fgetc(FILE *stream);
int getc(FILE *stream);
int getchar(void);
int ungetc(int byte, FILE *stream);
long ftell(FILE *stream);
int vfprintf(FILE *stream, const char *format, va_list arguments);
int fprintf(FILE *stream, const char *format, ...);
int vprintf(const char *format, va_list arguments);
int printf(const char *format, ...);
int vsnprintf(char *buffer, size_t size, const char *format, va_list arguments);
int snprintf(char *buffer, size_t size, const char *format, ...);
int vsprintf(char *buffer, const char *format, va_list arguments);
int sprintf(char *buffer, const char *format, ...);
void perror(const char *prefix);
#endif
