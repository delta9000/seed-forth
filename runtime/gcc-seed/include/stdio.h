#ifndef SEED_GCC_STDIO_H
#define SEED_GCC_STDIO_H
/* Original seed-forth interface; see LICENSE. Linux AMD64, single-threaded.
   Buffered streams (see ../STDIO-BUFFERING.md): stdout is line buffered on
   a terminal and fully buffered otherwise, stderr is unbuffered, files are
   fully buffered; exit() and return from main flush, _exit() does not.
   FILE is complete so that programs can declare FILE objects, but its
   members are private and have no host-libc layout compatibility.
   Formatting supports integer, pointer, narrow string/character, ASCII wide
   string/character, %n and exact floating conversions (../PRINTF-FLOAT.md);
   positional conversions fail. */
#include <stddef.h>
#include <stdarg.h>
#include <sys/types.h>
struct __seed_FILE {
    unsigned char *__rpos;
    unsigned char *__rend;
    unsigned char *__wpos;
    unsigned char *__wend;
    unsigned char *__wbase;
    unsigned char *__buf;
    size_t __size;
    int __fd;
    int __flags;
    int __mode;
    int __error;
    int __eof;
    struct __seed_FILE *__next;
    unsigned char __small[16];
};
typedef struct __seed_FILE FILE;
#define EOF (-1)
/* Default stream buffer size, also a recommended application block size. */
#define BUFSIZ 8192
#define _IOFBF 0
#define _IOLBF 1
#define _IONBF 2
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
int setvbuf(FILE *stream, char *buffer, int mode, size_t size);
void setbuf(FILE *stream, char *buffer);
void setbuffer(FILE *stream, char *buffer, size_t size);
void setlinebuf(FILE *stream);
int fclose(FILE *stream);
/* fflush(NULL) flushes every output stream. */
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
/* Single-threaded: the _unlocked forms and stream locks are trivial. */
int getc_unlocked(FILE *stream);
int getchar_unlocked(void);
int putc_unlocked(int byte, FILE *stream);
int putchar_unlocked(int byte);
void flockfile(FILE *stream);
int ftrylockfile(FILE *stream);
void funlockfile(FILE *stream);
char *fgets(char *buffer, int count, FILE *stream);
/* At least eight bytes of pushback are available. */
int ungetc(int byte, FILE *stream);
long ftell(FILE *stream);
int fseek(FILE *stream, long offset, int whence);
off_t ftello(FILE *stream);
int fseeko(FILE *stream, off_t offset, int whence);
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
/* Measured input: plain %d/%o/%x/%c, literals, %%, whitespace and %n.
   fscanf leaves the first unmatched byte unread in the stream. */
int sscanf(const char *text, const char *format, ...);
int fscanf(FILE *stream, const char *format, ...);
int remove(const char *path);
/* The kernel's atomic rename; an existing target file is replaced. */
int rename(const char *old, const char *new);
void perror(const char *prefix);
/* POSIX additions; see ../PROCESS-POSIX.md and ../STRINGS-POSIX.md. */
#define FILENAME_MAX 4096
#define P_tmpdir "/tmp"
/* MODE is "r" or "w", optionally followed by "e" (close-on-exec). */
FILE *popen(const char *command, const char *mode);
/* The child's wait status, or -1 (ECHILD) for a stream popen did not open. */
int pclose(FILE *stream);
/* Read through DELIMITER into a malloc'd *LINE (grown as needed) and
   NUL-terminate it; returns the byte count, or -1 at end of file/error.
   Declared only on request (as POSIX 2008 or GNU): older programs define
   their own getline with other types. See ../STRINGS-POSIX.md. */
#if defined _GNU_SOURCE || (defined _POSIX_C_SOURCE && _POSIX_C_SOURCE >= 200809L) \
    || (defined _XOPEN_SOURCE && _XOPEN_SOURCE >= 700)
ssize_t getdelim(char **line, size_t *capacity, int delimiter, FILE *stream);
ssize_t getline(char **line, size_t *capacity, FILE *stream);
#endif
#endif
