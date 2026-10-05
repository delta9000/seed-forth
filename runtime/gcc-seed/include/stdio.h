#ifndef SEED_GCC_STDIO_H
#define SEED_GCC_STDIO_H
/* Original seed-forth interface; see LICENSE. Linux AMD64, single-threaded.
   FILE is opaque and unbuffered. There is no host-libc FILE compatibility.
   Formatting supports integer, pointer, narrow string/character, ASCII wide
   string/character, and %n; floating and positional conversions fail. */
#include <stddef.h>
#include <stdarg.h>
typedef struct __seed_FILE FILE;
#define EOF (-1)
/* Recommended application I/O block size; FILE streams remain unbuffered. */
#define BUFSIZ 8192
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
FILE *__seed_stdin(void);
FILE *__seed_stdout(void);
FILE *__seed_stderr(void);
#define stdin (__seed_stdin())
#define stdout (__seed_stdout())
#define stderr (__seed_stderr())
FILE *fopen(const char *path, const char *mode);
FILE *freopen(const char *path, const char *mode, FILE *stream);
/* Ownership transfers only on success; w modes never truncate the fd. */
FILE *fdopen(int descriptor, const char *mode);
/* Only NULL buffer is supported; non-NULL terminates immediately with status 127. */
void setbuf(FILE *stream, char *buffer);
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
char *fgets(char *buffer, int count, FILE *stream);
int ungetc(int byte, FILE *stream);
long ftell(FILE *stream);
int fseek(FILE *stream, long offset, int whence);
/* fseek to offset 0, then clear the error and end-of-file indicators. */
void rewind(FILE *stream);
int fileno(FILE *stream);
int vfprintf(FILE *stream, const char *format, va_list arguments);
int fprintf(FILE *stream, const char *format, ...);
int vprintf(const char *format, va_list arguments);
int printf(const char *format, ...);
int vsnprintf(char *buffer, size_t size, const char *format, va_list arguments);
int snprintf(char *buffer, size_t size, const char *format, ...);
int vsprintf(char *buffer, const char *format, va_list arguments);
int sprintf(char *buffer, const char *format, ...);
/* Measured input: plain %d/%o/%x/%c, literals, %% and whitespace.
   fscanf leaves the first unmatched byte unread in the stream. */
int sscanf(const char *text, const char *format, ...);
int fscanf(FILE *stream, const char *format, ...);
int remove(const char *path);
/* The kernel's atomic rename; an existing target file is replaced. */
int rename(const char *old, const char *new);
void perror(const char *prefix);
#endif
