/* Original seed-forth implementation; distributed under ../../LICENSE.
   Buffered Linux AMD64 streams (see ../STDIO-BUFFERING.md) and the printf
   family, including exact floating conversions (../PRINTF-FLOAT.md). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <errno.h>
#include <seed-syscall.h>
#include <fcntl.h>
#include <wchar.h>
#include <seed-float.h>

#define SEED_READ 1
#define SEED_WRITE 2
#define SEED_OWNED 4
#define SEED_OWN_BUFFER 8
#define SEED_APPEND 16
#define SEED_MODE_SET 32
#define SEED_EOVERFLOW 75
/* Bytes kept before every buffer so ungetc always has room. */
#define SEED_UNGET 8

/* Set while any stream exists; exit() calls it to flush output. */
extern void (*__seed_exit_flush)(void);

static FILE seed_input;
static FILE seed_output;
static FILE seed_error;
static int seed_streams_ready;
static FILE *seed_streams;

static void seed_flush_all_output(void);

static void seed_streams_init(void)
{
    if (!seed_streams_ready) {
        seed_input.__fd = 0;
        seed_input.__flags = SEED_READ;
        seed_output.__fd = 1;
        seed_output.__flags = SEED_WRITE;
        seed_error.__fd = 2;
        seed_error.__flags = SEED_WRITE | SEED_MODE_SET;
        seed_error.__mode = _IONBF;
        seed_streams_ready = 1;
        __seed_exit_flush = seed_flush_all_output;
    }
}

FILE *__seed_stdin(void) { seed_streams_init(); return &seed_input; }
FILE *__seed_stdout(void) { seed_streams_init(); return &seed_output; }
FILE *__seed_stderr(void) { seed_streams_init(); return &seed_error; }

static long seed_call(long number, long a1, long a2, long a3)
{
    long result;
    do {
        result = __seed_syscall6(number, a1, a2, a3, 0, 0, 0);
    } while (result == -EINTR);
    return result;
}

static int seed_stream_check(FILE *stream, int access)
{
    if (stream == NULL || stream->__fd < 0 || !(stream->__flags & access)) {
        errno = EBADF;
        if (stream != NULL) stream->__error = 1;
        return 0;
    }
    return 1;
}

/* Every stream other than the three standard ones, for fflush(NULL). */
static void seed_list_add(FILE *stream)
{
    seed_streams_init();
    stream->__next = seed_streams;
    seed_streams = stream;
}

static void seed_list_remove(FILE *stream)
{
    FILE **link = &seed_streams;
    while (*link) {
        if (*link == stream) {
            *link = stream->__next;
            return;
        }
        link = &(*link)->__next;
    }
}

/* A terminal (TCGETS succeeds) gets line buffering, as in glibc. */
static int seed_is_terminal(int descriptor)
{
    unsigned char termios[64];
    return __seed_syscall6(16, descriptor, 0x5401, (long)termios, 0, 0, 0) == 0;
}

static void seed_reset_buffer(FILE *stream)
{
    stream->__rpos = NULL;
    stream->__rend = NULL;
    stream->__wpos = NULL;
    stream->__wend = NULL;
    stream->__wbase = NULL;
}

static void seed_release_buffer(FILE *stream)
{
    if (stream->__flags & SEED_OWN_BUFFER) free(stream->__buf - SEED_UNGET);
    stream->__flags &= ~SEED_OWN_BUFFER;
    stream->__buf = NULL;
    stream->__size = 0;
    seed_reset_buffer(stream);
}

/* Choose the mode on first use and allocate the buffer. Unbuffered
   streams read through a one-byte area inside the FILE. */
static void seed_buffer(FILE *stream)
{
    unsigned char *memory;
    if (stream->__buf) return;
    if (!(stream->__flags & SEED_MODE_SET)) {
        stream->__mode = seed_is_terminal(stream->__fd) ? _IOLBF : _IOFBF;
        stream->__flags |= SEED_MODE_SET;
    }
    if (stream->__mode != _IONBF) {
        memory = malloc(BUFSIZ + SEED_UNGET);
        if (memory != NULL) {
            stream->__buf = memory + SEED_UNGET;
            stream->__size = BUFSIZ;
            stream->__flags |= SEED_OWN_BUFFER;
            return;
        }
        stream->__mode = _IONBF; /* no memory: degrade to unbuffered */
    }
    stream->__buf = stream->__small + SEED_UNGET;
    stream->__size = 1;
}

/* Write LENGTH bytes straight to the descriptor; returns bytes written. */
static size_t seed_write_out(FILE *stream, const unsigned char *data, size_t length)
{
    size_t done = 0;
    size_t part;
    long result;
    while (done < length) {
        part = length - done;
        if (part > 2147479552UL) part = 2147479552UL;
        result = __seed_syscall6(1, stream->__fd, (long)(data + done), (long)part, 0, 0, 0);
        if (result == -EINTR) continue;
        if (result <= 0) {
            errno = result < 0 ? (int)-result : EIO;
            stream->__error = 1;
            break;
        }
        done += (size_t)result;
    }
    return done;
}

/* Write out pending output. A failed write drops the unwritten bytes. */
static int seed_flush_write(FILE *stream)
{
    size_t pending;
    int failed = 0;
    if (stream->__wpos == NULL) return 0;
    pending = (size_t)(stream->__wpos - stream->__wbase);
    if (pending && seed_write_out(stream, stream->__wbase, pending) != pending) failed = 1;
    stream->__wbase = stream->__buf;
    stream->__wpos = stream->__buf;
    return failed ? EOF : 0;
}

static void seed_flush_all_output(void)
{
    FILE *stream;
    if (seed_output.__wpos) seed_flush_write(&seed_output);
    if (seed_error.__wpos) seed_flush_write(&seed_error);
    for (stream = seed_streams; stream; stream = stream->__next)
        if (stream->__wpos) seed_flush_write(stream);
}

/* C: reading a line-buffered or unbuffered stream from the host first
   transmits every line-buffered output stream. */
static void seed_flush_line_output(void)
{
    FILE *stream;
    if (seed_output.__wpos && seed_output.__mode == _IOLBF) seed_flush_write(&seed_output);
    for (stream = seed_streams; stream; stream = stream->__next)
        if (stream->__wpos && stream->__mode == _IOLBF) seed_flush_write(stream);
}

/* Give unread buffered input back to the descriptor's file offset.
   Unseekable descriptors keep their buffer, as in glibc. */
static int seed_sync_read(FILE *stream)
{
    long unread;
    long result;
    if (stream->__rpos == NULL) return 0;
    unread = (long)(stream->__rend - stream->__rpos);
    if (unread) {
        result = seed_call(8, stream->__fd, -unread, SEEK_CUR);
        if (result < 0) {
            if (result == -29) return 0; /* ESPIPE */
            errno = (int)-result;
            stream->__error = 1;
            return EOF;
        }
    }
    stream->__rpos = NULL;
    stream->__rend = NULL;
    return 0;
}

/* Enter output mode; 0 on success. */
static int seed_to_write(FILE *stream)
{
    if (!seed_stream_check(stream, SEED_WRITE)) return EOF;
    if (stream->__wpos) return 0;
    if (stream->__rpos) {
        if (seed_sync_read(stream)) return EOF;
        stream->__rpos = NULL;
        stream->__rend = NULL;
    }
    seed_buffer(stream);
    if (stream->__mode == _IONBF) return 0;
    stream->__wbase = stream->__buf;
    stream->__wpos = stream->__buf;
    /* Line-buffered output always takes the slow path to see newlines. */
    stream->__wend = stream->__mode == _IOFBF ? stream->__buf + stream->__size : stream->__buf;
    return 0;
}

/* Append LENGTH bytes; returns the count accepted. */
static size_t seed_put(FILE *stream, const unsigned char *data, size_t length)
{
    size_t room;
    size_t done = 0;
    size_t part;
    unsigned char *end;
    if (seed_to_write(stream)) return 0;
    if (stream->__mode == _IONBF) return seed_write_out(stream, data, length);
    end = stream->__buf + stream->__size;
    while (done < length) {
        room = (size_t)(end - stream->__wpos);
        if (room == 0) {
            if (seed_flush_write(stream)) return done;
            continue;
        }
        if (stream->__wpos == stream->__wbase && length - done >= stream->__size) {
            /* Nothing pending and at least a buffer's worth: write it now. */
            part = length - done;
            return done + seed_write_out(stream, data + done, part);
        }
        part = length - done < room ? length - done : room;
        memcpy(stream->__wpos, data + done, part);
        stream->__wpos += part;
        done += part;
    }
    if (stream->__mode == _IOLBF && memchr(data, '\n', length) && seed_flush_write(stream))
        return 0;
    return done;
}

/* Enter input mode and make buffered bytes available: the count, 0 at
   end of file (sticky), or -1 after an error. */
static long seed_fill(FILE *stream)
{
    long result;
    if (stream->__rpos && stream->__rpos < stream->__rend)
        return (long)(stream->__rend - stream->__rpos);
    if (!seed_stream_check(stream, SEED_READ)) return -1;
    if (stream->__wpos) {
        if (seed_flush_write(stream)) return -1;
        stream->__wpos = NULL;
        stream->__wend = NULL;
        stream->__wbase = NULL;
    }
    if (stream->__eof) return 0;
    seed_buffer(stream);
    if (stream->__mode != _IOFBF) seed_flush_line_output();
    result = seed_call(0, stream->__fd, (long)stream->__buf, (long)stream->__size);
    if (result < 0) {
        errno = (int)-result;
        stream->__error = 1;
        return -1;
    }
    stream->__rpos = stream->__buf;
    stream->__rend = stream->__buf + result;
    if (result == 0) stream->__eof = 1;
    return result;
}

static int seed_open_mode(const char *mode, int *flags, int *access)
{
    int binary = 0;
    int update = 0;
    int index = 1;
    if (mode == NULL) { errno = EINVAL; return 0; }
    if (mode[0] == 'r') { *flags = O_RDONLY; *access = SEED_READ; }
    else if (mode[0] == 'w') { *flags = O_WRONLY | O_CREAT | O_TRUNC; *access = SEED_WRITE; }
    else if (mode[0] == 'a') { *flags = O_WRONLY | O_CREAT | O_APPEND; *access = SEED_WRITE | SEED_APPEND; }
    else { errno = EINVAL; return 0; }
    /* After the first letter, glibc honours 'x' (O_EXCL) and 'e' (O_CLOEXEC),
       ignores the 't', 'm' and 'c' extensions and stops at ",ccs=".  sed
       4.0.9 opens -f scripts with "rt".  A repeated '+' or 'b' is rejected. */
    while (mode[index] && mode[index] != ',') {
        if (mode[index] == '+' && !update) update = 1;
        else if (mode[index] == 'b' && !binary) binary = 1;
        else if (mode[index] == 'x' && mode[0] == 'w') *flags |= O_EXCL;
        else if (mode[index] == 'e') *flags |= O_CLOEXEC;
        else if (mode[index] == 't' || mode[index] == 'm' || mode[index] == 'c') ;
        else { errno = EINVAL; return 0; }
        index++;
    }
    if (update) {
        *flags = (*flags & ~O_ACCMODE) | O_RDWR;
        *access |= SEED_READ | SEED_WRITE;
    }
    return 1;
}

static void seed_stream_init(FILE *stream, int descriptor, int access)
{
    memset(stream, 0, sizeof(FILE));
    stream->__fd = descriptor;
    stream->__flags = access | SEED_OWNED;
}

FILE *fopen(const char *path, const char *mode)
{
    int flags;
    int access;
    long descriptor;
    FILE *stream;
    if (!seed_open_mode(mode, &flags, &access)) return NULL;
    stream = malloc(sizeof(FILE));
    if (stream == NULL) return NULL;
    descriptor = seed_call(2, (long)path, flags, 0666);
    if (descriptor < 0) {
        errno = (int)-descriptor;
        free(stream);
        return NULL;
    }
    seed_stream_init(stream, (int)descriptor, access);
    seed_list_add(stream);
    return stream;
}

FILE *fdopen(int descriptor, const char *mode)
{
    int flags;
    int access;
    int actual_access;
    long actual_flags;
    long result;
    FILE *stream;
    if (!seed_open_mode(mode, &flags, &access)) return NULL;
    actual_flags = seed_call(72, descriptor, F_GETFL, 0);
    if (actual_flags < 0) { errno = (int)-actual_flags; return NULL; }
    /* Linux O_PATH descriptors cannot supply stream I/O. */
    if (actual_flags & 2097152L) { errno = EBADF; return NULL; }
    actual_access = (int)actual_flags & O_ACCMODE;
    if (actual_access == O_ACCMODE
        || ((access & SEED_READ) && actual_access == O_WRONLY)
        || ((access & SEED_WRITE) && actual_access == O_RDONLY)) {
        errno = EINVAL;
        return NULL;
    }
    stream = malloc(sizeof(FILE));
    if (stream == NULL) return NULL;
    if ((flags & O_APPEND) && !(actual_flags & O_APPEND)) {
        result = seed_call(72, descriptor, F_SETFL, actual_flags | O_APPEND);
        if (result < 0) {
            errno = (int)-result;
            free(stream);
            return NULL;
        }
    }
    seed_stream_init(stream, descriptor, access);
    seed_list_add(stream);
    return stream;
}

FILE *freopen(const char *path, const char *mode, FILE *stream)
{
    int flags;
    int access;
    int previous;
    int owned;
    int error;
    long descriptor;
    long result;
    FILE *next;
    if (!seed_open_mode(mode, &flags, &access)) return NULL;
    if (!seed_stream_check(stream, SEED_READ | SEED_WRITE)) return NULL;
    /* Pending output is written first; errors from it and from close are
       ignored, as freopen has no way to report them separately. */
    if (stream->__wpos) seed_flush_write(stream);
    previous = stream->__fd;
    owned = stream->__flags & SEED_OWNED;
    /* Linux close releases the descriptor even on EINTR; never retried. */
    __seed_syscall6(3, previous, 0, 0, 0, 0, 0);
    seed_release_buffer(stream);
    next = stream->__next;
    memset(stream, 0, sizeof(FILE));
    stream->__next = next;
    stream->__fd = -1;
    descriptor = -EINVAL;
    /* No filename-null mode changes are supported by this implementation. */
    if (path != NULL) descriptor = seed_call(2, (long)path, flags, 0666);
    if (descriptor >= 0 && descriptor != previous) {
        result = seed_call(33, descriptor, previous, 0);
        __seed_syscall6(3, descriptor, 0, 0, 0, 0, 0);
        descriptor = result;
    }
    if (descriptor < 0) {
        error = (int)-descriptor;
        if (owned) {
            seed_list_remove(stream);
            free(stream);
        }
        errno = error;
        return NULL;
    }
    stream->__fd = (int)descriptor;
    stream->__flags = access | owned;
    if (stream == &seed_error) {
        stream->__flags |= SEED_MODE_SET;
        stream->__mode = _IONBF;
    }
    return stream;
}

int fclose(FILE *stream)
{
    long result;
    int owned;
    int failed = 0;
    int saved = 0;
    if (!seed_stream_check(stream, SEED_READ | SEED_WRITE)) return EOF;
    if (stream->__wpos && seed_flush_write(stream)) {
        failed = 1;
        saved = errno;
    }
    if (stream->__rpos && (stream->__flags & SEED_READ)) seed_sync_read(stream);
    owned = stream->__flags & SEED_OWNED;
    /* Linux releases the descriptor even when close reports EINTR. Retrying
       could close an unrelated descriptor that reused the same number. */
    result = __seed_syscall6(3, stream->__fd, 0, 0, 0, 0, 0);
    seed_release_buffer(stream);
    stream->__fd = -1;
    stream->__flags = 0;
    if (owned) {
        seed_list_remove(stream);
        free(stream);
    }
    if (failed) { errno = saved; return EOF; }
    if (result < 0) { errno = (int)-result; return EOF; }
    return 0;
}

int fflush(FILE *stream)
{
    if (stream == NULL) {
        FILE *each;
        int failed = 0;
        if (!seed_streams_ready) return 0;
        if (seed_output.__wpos && seed_flush_write(&seed_output)) failed = 1;
        if (seed_error.__wpos && seed_flush_write(&seed_error)) failed = 1;
        for (each = seed_streams; each; each = each->__next)
            if (each->__wpos && seed_flush_write(each)) failed = 1;
        return failed ? EOF : 0;
    }
    if (!seed_stream_check(stream, SEED_READ | SEED_WRITE)) return EOF;
    if (stream->__wpos) return seed_flush_write(stream);
    /* An input stream gives unread bytes back to a seekable file offset. */
    return seed_sync_read(stream);
}

int setvbuf(FILE *stream, char *buffer, int mode, size_t size)
{
    if (mode != _IOFBF && mode != _IOLBF && mode != _IONBF) {
        errno = EINVAL;
        return EOF;
    }
    if (!seed_stream_check(stream, SEED_READ | SEED_WRITE)) return EOF;
    /* C requires this before other operations; tolerate later calls by
       first writing pending output and giving back unread input. */
    if (stream->__wpos && seed_flush_write(stream)) return EOF;
    if (stream->__rpos) seed_sync_read(stream);
    seed_release_buffer(stream);
    stream->__mode = mode;
    stream->__flags |= SEED_MODE_SET;
    if (mode != _IONBF && buffer != NULL && size > 2 * SEED_UNGET) {
        /* The caller's buffer, less room reserved for ungetc. */
        stream->__buf = (unsigned char *)buffer + SEED_UNGET;
        stream->__size = size - SEED_UNGET;
    }
    return 0;
}

void setbuffer(FILE *stream, char *buffer, size_t size)
{
    setvbuf(stream, buffer, buffer ? _IOFBF : _IONBF, size);
}

void setlinebuf(FILE *stream)
{
    setvbuf(stream, NULL, _IOLBF, 0);
}

int ferror(FILE *stream) { return stream->__error != 0; }
int feof(FILE *stream) { return stream->__eof != 0; }
void clearerr(FILE *stream) { stream->__error = 0; stream->__eof = 0; }

size_t fwrite(const void *data, size_t size, size_t count, FILE *stream)
{
    if (size == 0 || count == 0) return 0;
    if (count > (size_t)-1 / size) {
        errno = SEED_EOVERFLOW;
        stream->__error = 1;
        return 0;
    }
    return seed_put(stream, data, size * count) / size;
}

size_t fread(void *data, size_t size, size_t count, FILE *stream)
{
    unsigned char *destination = data;
    size_t total;
    size_t done = 0;
    size_t part;
    long result;
    if (size == 0 || count == 0) return 0;
    if (!seed_stream_check(stream, SEED_READ)) return 0;
    if (count > (size_t)-1 / size) {
        errno = SEED_EOVERFLOW;
        stream->__error = 1;
        return 0;
    }
    total = size * count;
    if (stream->__wpos) {
        if (seed_flush_write(stream)) return 0;
        stream->__wpos = NULL;
        stream->__wend = NULL;
        stream->__wbase = NULL;
    }
    seed_buffer(stream);
    while (done < total) {
        if (stream->__rpos && stream->__rpos < stream->__rend) {
            part = (size_t)(stream->__rend - stream->__rpos);
            if (part > total - done) part = total - done;
            memcpy(destination + done, stream->__rpos, part);
            stream->__rpos += part;
            done += part;
            continue;
        }
        if (stream->__eof) break;
        if (total - done >= stream->__size) {
            /* Large reads bypass the buffer; the stream position stays
               the descriptor's offset because nothing is left buffered. */
            if (stream->__mode != _IOFBF) seed_flush_line_output();
            part = total - done;
            if (part > 2147479552UL) part = 2147479552UL;
            result = seed_call(0, stream->__fd, (long)(destination + done), (long)part);
            if (result < 0) { errno = (int)-result; stream->__error = 1; break; }
            if (result == 0) { stream->__eof = 1; break; }
            done += (size_t)result;
            continue;
        }
        if (seed_fill(stream) <= 0) break;
    }
    return done / size;
}

int fputc(int byte, FILE *stream)
{
    unsigned char value = (unsigned char)byte;
    if (stream->__wpos < stream->__wend) {
        *stream->__wpos++ = value;
        return value;
    }
    if (seed_to_write(stream)) return EOF;
    if (stream->__mode == _IONBF)
        return seed_write_out(stream, &value, 1) == 1 ? value : EOF;
    if (stream->__wpos == stream->__buf + stream->__size && seed_flush_write(stream)) return EOF;
    *stream->__wpos++ = value;
    if ((stream->__mode == _IOLBF && value == '\n')
        || stream->__wpos == stream->__buf + stream->__size) {
        if (seed_flush_write(stream)) return EOF;
    }
    return value;
}
int putc(int byte, FILE *stream) { return fputc(byte, stream); }
int putchar(int byte) { return fputc(byte, stdout); }
int fputs(const char *text, FILE *stream)
{
    size_t size = strlen(text);
    if (seed_to_write(stream)) return EOF;
    return seed_put(stream, (const unsigned char *)text, size) == size ? 0 : EOF;
}
int puts(const char *text)
{
    FILE *stream = stdout;
    size_t size = strlen(text);
    if (seed_to_write(stream)) return EOF;
    if (seed_put(stream, (const unsigned char *)text, size) != size) return EOF;
    return fputc('\n', stream) == EOF ? EOF : 0;
}
int fgetc(FILE *stream)
{
    if (stream->__rpos < stream->__rend) return *stream->__rpos++;
    if (seed_fill(stream) <= 0) return EOF;
    return *stream->__rpos++;
}
int getc(FILE *stream) { return fgetc(stream); }
int getchar(void) { return fgetc(stdin); }
int getc_unlocked(FILE *stream) { return fgetc(stream); }
int getchar_unlocked(void) { return fgetc(stdin); }
int putc_unlocked(int byte, FILE *stream) { return fputc(byte, stream); }
int putchar_unlocked(int byte) { return fputc(byte, stdout); }
void flockfile(FILE *stream) { (void)stream; }
int ftrylockfile(FILE *stream) { (void)stream; return 0; }
void funlockfile(FILE *stream) { (void)stream; }

char *fgets(char *buffer, int count, FILE *stream)
{
    int used = 0;
    int previous_error;
    int failed;
    size_t part;
    unsigned char *newline;
    if (count <= 0) { errno = EINVAL; return NULL; }
    if (!seed_stream_check(stream, SEED_READ)) return NULL;
    if (count == 1) { buffer[0] = 0; return buffer; }
    /* Distinguish a new read failure from a previously sticky indicator. */
    previous_error = stream->__error;
    stream->__error = 0;
    while (used < count - 1) {
        if (!(stream->__rpos < stream->__rend) && seed_fill(stream) <= 0) break;
        part = (size_t)(stream->__rend - stream->__rpos);
        if (part > (size_t)(count - 1 - used)) part = (size_t)(count - 1 - used);
        newline = memchr(stream->__rpos, '\n', part);
        if (newline) part = (size_t)(newline - stream->__rpos) + 1;
        memcpy(buffer + used, stream->__rpos, part);
        stream->__rpos += part;
        used += (int)part;
        if (newline) break;
    }
    failed = stream->__error;
    stream->__error = previous_error || failed;
    if (failed || used == 0) return NULL;
    buffer[used] = 0;
    return buffer;
}

int ungetc(int byte, FILE *stream)
{
    if (byte == EOF) return EOF;
    if (!seed_stream_check(stream, SEED_READ)) return EOF;
    if (!stream->__rpos) {
        if (stream->__wpos) {
            if (seed_flush_write(stream)) return EOF;
            stream->__wpos = NULL;
            stream->__wend = NULL;
            stream->__wbase = NULL;
        }
        seed_buffer(stream);
        stream->__rpos = stream->__buf;
        stream->__rend = stream->__buf;
    }
    if (stream->__rpos <= stream->__buf - SEED_UNGET) return EOF;
    *--stream->__rpos = (unsigned char)byte;
    stream->__eof = 0;
    return (unsigned char)byte;
}

long ftell(FILE *stream)
{
    long result;
    if (!seed_stream_check(stream, SEED_READ | SEED_WRITE)) return -1;
    if (stream->__wpos && (stream->__flags & SEED_APPEND)) {
        /* Appended bytes land at end of file: write them to learn where. */
        if (seed_flush_write(stream)) return -1;
    }
    result = seed_call(8, stream->__fd, 0, SEEK_CUR);
    if (result < 0) { errno = (int)-result; return -1; }
    if (stream->__wpos) result += (long)(stream->__wpos - stream->__wbase);
    if (stream->__rpos) result -= (long)(stream->__rend - stream->__rpos);
    return result;
}

int fseek(FILE *stream, long offset, int whence)
{
    long result;
    long unread = 0;
    if (!seed_stream_check(stream, SEED_READ | SEED_WRITE)) return -1;
    if (whence != SEEK_SET && whence != SEEK_CUR && whence != SEEK_END) {
        errno = EINVAL;
        return -1;
    }
    if (stream->__wpos && seed_flush_write(stream)) return -1;
    if (stream->__rpos) unread = (long)(stream->__rend - stream->__rpos);
    if (whence == SEEK_CUR && unread) {
        if (offset < LONG_MIN + unread) { errno = EOVERFLOW; return -1; }
        offset -= unread;
    }
    result = seed_call(8, stream->__fd, offset, whence);
    if (result < 0) { errno = (int)-result; return -1; }
    seed_reset_buffer(stream);
    stream->__eof = 0;
    return 0;
}

int fseeko(FILE *stream, off_t offset, int whence) { return fseek(stream, (long)offset, whence); }
off_t ftello(FILE *stream) { return (off_t)ftell(stream); }

void rewind(FILE *stream)
{
    /* A failed seek keeps its errno; both indicators are cleared anyway. */
    (void)fseek(stream, 0L, SEEK_SET);
    if (stream != NULL) clearerr(stream);
}

int fileno(FILE *stream)
{
    if (stream == NULL || stream->__fd < 0) { errno = EBADF; return -1; }
    return stream->__fd;
}

wint_t getwc(FILE *stream)
{
    int byte = fgetc(stream);
    if (byte == EOF) return WEOF;
    if (byte > 127) {
        errno = EILSEQ;
        stream->__error = 1;
        return WEOF;
    }
    return (wint_t)byte;
}

struct seed_print {
    FILE *stream;
    char *buffer;
    size_t capacity;
    int count;
    int failed;
};

static int seed_print_error(struct seed_print *output, int error)
{
    errno = error;
    output->failed = 1;
    return 0;
}

static int seed_print_bytes(struct seed_print *output, const char *text, size_t size)
{
    size_t room;
    size_t copy;
    if (size > (size_t)(INT_MAX - output->count))
        return seed_print_error(output, SEED_EOVERFLOW);
    if (output->stream != NULL) {
        if (seed_put(output->stream, (const unsigned char *)text, size) != size) {
            output->failed = 1;
            return 0;
        }
    } else if (output->capacity > 0 && (size_t)output->count < output->capacity - 1) {
        room = output->capacity - 1 - (size_t)output->count;
        copy = size < room ? size : room;
        memcpy(output->buffer + output->count, text, copy);
    }
    output->count = output->count + (int)size;
    return 1;
}

static int seed_print_padding(struct seed_print *output, char byte, int count)
{
    char block[64];
    int part;
    size_t room;
    if (count <= 0) return 1;
    if (count > INT_MAX - output->count)
        return seed_print_error(output, SEED_EOVERFLOW);
    /* A truncated snprintf still counts the full padding, in bounded time. */
    if (output->stream == NULL) {
        if (output->capacity > 0 && (size_t)output->count < output->capacity - 1) {
            room = output->capacity - 1 - (size_t)output->count;
            if (room > (size_t)count) room = (size_t)count;
            memset(output->buffer + output->count, byte, room);
        }
        output->count = output->count + count;
        return 1;
    }
    memset(block, byte, sizeof(block));
    while (count > 0) {
        part = count < 64 ? count : 64;
        if (!seed_print_bytes(output, block, part)) return 0;
        count = count - part;
    }
    return 1;
}

static int seed_print_decimal(const char **format, int *value)
{
    int digit;
    *value = 0;
    while (**format >= '0' && **format <= '9') {
        digit = **format - '0';
        if (*value > (INT_MAX - digit) / 10) return 0;
        *value = *value * 10 + digit;
        *format = *format + 1;
    }
    return 1;
}

static int seed_print_wide(struct seed_print *output, const wchar_t *text,
                           int width, int precision, int left)
{
    static const wchar_t missing[] = {'(', 'n', 'u', 'l', 'l', ')', 0};
    size_t size = 0;
    size_t index;
    int padding;
    char byte;
    if (text == NULL) text = missing;
    while ((precision < 0 || size < (size_t)precision) && text[size]) {
        if ((unsigned int)text[size] > 127) return seed_print_error(output, EILSEQ);
        size++;
    }
    if (size > INT_MAX) return seed_print_error(output, SEED_EOVERFLOW);
    padding = width > (int)size ? width - (int)size : 0;
    if (!left && !seed_print_padding(output, ' ', padding)) return 0;
    for (index = 0; index < size; index++) {
        byte = (char)text[index];
        if (!seed_print_bytes(output, &byte, 1)) return 0;
    }
    return !left || seed_print_padding(output, ' ', padding);
}

/* Write one floating conversion: '0' pads after the sign and any 0x
   prefix, except for infinities and NaNs, which pad with spaces. */
static int seed_print_float(struct seed_print *output, struct __seed_float_text *text,
                            int width, int left, int zero)
{
    long total;
    long padding;
    size_t prefix = strlen(text->prefix);
    total = (text->sign != 0) + (long)prefix + text->lead_len + (long)text->lead_zeros
            + text->point + (long)text->frac_zeros + text->frac_len
            + (long)text->trail_zeros + text->suffix_len;
    if (total > INT_MAX) return seed_print_error(output, SEED_EOVERFLOW);
    padding = width > total ? width - total : 0;
    if (text->special) zero = 0;
    if (!left && !zero && !seed_print_padding(output, ' ', (int)padding)) return 0;
    if (text->sign && !seed_print_bytes(output, &text->sign, 1)) return 0;
    if (!seed_print_bytes(output, text->prefix, prefix)) return 0;
    if (!left && zero && !seed_print_padding(output, '0', (int)padding)) return 0;
    if (!seed_print_bytes(output, text->lead, (size_t)text->lead_len)) return 0;
    if (!seed_print_padding(output, '0', text->lead_zeros)) return 0;
    if (text->point && !seed_print_bytes(output, ".", 1)) return 0;
    if (!seed_print_padding(output, '0', text->frac_zeros)) return 0;
    if (!seed_print_bytes(output, text->frac, (size_t)text->frac_len)) return 0;
    if (!seed_print_padding(output, '0', text->trail_zeros)) return 0;
    if (!seed_print_bytes(output, text->suffix, (size_t)text->suffix_len)) return 0;
    return !left || seed_print_padding(output, ' ', (int)padding);
}

static int seed_format(struct seed_print *output, const char *format, va_list arguments)
{
    const char *begin;
    const char *text;
    const char *digits;
    const wchar_t *wide_text;
    wint_t wide_character;
    char number[32];
    char prefix[3];
    char character;
    int left;
    int plus;
    int blank;
    int alternate;
    int zero;
    int width;
    int precision;
    int length;
    int wide_length;
    int conversion;
    int base;
    int used;
    int prefix_size;
    int zeros;
    int padding;
    int content;
    size_t size;
    long signed_value;
    unsigned long value;
    while (*format && !output->failed) {
        begin = format;
        while (*format && *format != '%') format = format + 1;
        if (!seed_print_bytes(output, begin, (size_t)(format - begin))) break;
        if (!*format) break;
        format = format + 1;
        left = 0; plus = 0; blank = 0; alternate = 0; zero = 0;
        while (*format == '-' || *format == '+' || *format == ' ' || *format == '#' || *format == '0') {
            if (*format == '-') left = 1;
            if (*format == '+') plus = 1;
            if (*format == ' ') blank = 1;
            if (*format == '#') alternate = 1;
            if (*format == '0') zero = 1;
            format = format + 1;
        }
        width = 0;
        if (*format == '*') {
            width = va_arg(arguments, int);
            format = format + 1;
            if (width == INT_MIN) { seed_print_error(output, SEED_EOVERFLOW); break; }
            if (width < 0) { left = 1; width = -width; }
        } else if (!seed_print_decimal(&format, &width)) {
            seed_print_error(output, SEED_EOVERFLOW); break;
        }
        precision = -1;
        if (*format == '.') {
            format = format + 1;
            if (*format == '*') {
                precision = va_arg(arguments, int);
                format = format + 1;
                if (precision < 0) precision = -1;
            } else if (!seed_print_decimal(&format, &precision)) {
                seed_print_error(output, SEED_EOVERFLOW); break;
            }
        }
        length = 0;
        wide_length = 0;
        if (*format == 'h') {
            format = format + 1; length = 1;
            if (*format == 'h') { format = format + 1; length = 2; }
        } else if (*format == 'l') {
            format = format + 1; length = 3; wide_length = 1;
            if (*format == 'l') { format = format + 1; length = 4; }
        } else if (*format == 'z' || *format == 't' || *format == 'j') {
            length = 3; format = format + 1;
        } else if (*format == 'L') {
            /* long double for floating conversions; long long otherwise. */
            length = 4; format = format + 1;
        }
        conversion = (unsigned char)*format;
        if (*format) format = format + 1;
        if (conversion == 'n') {
            if (length == 2) *va_arg(arguments, signed char *) = (signed char)output->count;
            else if (length == 1) *va_arg(arguments, short *) = (short)output->count;
            else if (length == 3) *va_arg(arguments, long *) = output->count;
            else if (length == 4) *va_arg(arguments, long long *) = output->count;
            else *va_arg(arguments, int *) = output->count;
            continue;
        }
        if (conversion == 's' || conversion == 'c' || conversion == '%') {
            if (length) {
                if (!wide_length || length != 3 || conversion == '%') {
                    seed_print_error(output, EINVAL); break;
                }
                if (conversion == 's') {
                    wide_text = va_arg(arguments, const wchar_t *);
                    if (!seed_print_wide(output, wide_text, width, precision, left)) break;
                    continue;
                }
                wide_character = va_arg(arguments, wint_t);
                if (wide_character > 127) { seed_print_error(output, EILSEQ); break; }
                character = (char)wide_character;
                text = &character;
                size = 1;
            } else if (conversion == 's') {
                text = va_arg(arguments, char *);
                if (text == NULL) text = "(null)";
                size = 0;
                while ((precision < 0 || size < (size_t)precision) && text[size]) size = size + 1;
            } else {
                character = conversion == '%' ? '%' : (char)va_arg(arguments, int);
                text = &character;
                size = 1;
            }
            if (size > INT_MAX) { seed_print_error(output, SEED_EOVERFLOW); break; }
            padding = width > (int)size ? width - (int)size : 0;
            if (!left && !seed_print_padding(output, ' ', padding)) break;
            if (!seed_print_bytes(output, text, size)) break;
            if (left && !seed_print_padding(output, ' ', padding)) break;
            continue;
        }
        if (conversion == 'e' || conversion == 'E' || conversion == 'f' || conversion == 'F'
            || conversion == 'g' || conversion == 'G' || conversion == 'a' || conversion == 'A') {
            struct __seed_float_text float_text;
            unsigned char float_bytes[16];
            if (length == 4) {
                /* L and ll select long double, as in glibc. */
                long double long_value = va_arg(arguments, long double);
                memcpy(float_bytes, &long_value, 10);
            } else {
                double double_value = va_arg(arguments, double);
                memcpy(float_bytes, &double_value, 8);
            }
            __seed_float_format(&float_text, float_bytes, length == 4, conversion, precision,
                                alternate, plus, blank);
            if (!seed_print_float(output, &float_text, width, left, zero)) break;
            continue;
        }
        if (conversion != 'd' && conversion != 'i' && conversion != 'u' &&
            conversion != 'o' && conversion != 'x' && conversion != 'X' && conversion != 'p') {
            /* In particular, do not consume an SSE argument as an integer. */
            seed_print_error(output, EINVAL); break;
        }
        prefix_size = 0;
        if (conversion == 'd' || conversion == 'i') {
            if (length == 4) signed_value = va_arg(arguments, long long);
            else if (length == 3) signed_value = va_arg(arguments, long);
            else signed_value = va_arg(arguments, int);
            if (length == 1) signed_value = (short)signed_value;
            if (length == 2) signed_value = (signed char)signed_value;
            value = (unsigned long)signed_value;
            if (signed_value < 0) { prefix[prefix_size++] = '-'; value = 0UL - value; }
            else if (plus) prefix[prefix_size++] = '+';
            else if (blank) prefix[prefix_size++] = ' ';
        } else {
            if (conversion == 'p') {
                if (length) { seed_print_error(output, EINVAL); break; }
                value = (unsigned long)va_arg(arguments, void *);
            } else if (length == 4) value = va_arg(arguments, unsigned long long);
            else if (length == 3) value = va_arg(arguments, unsigned long);
            else value = va_arg(arguments, unsigned int);
            if (length == 1) value = (unsigned short)value;
            if (length == 2) value = (unsigned char)value;
        }
        base = 10;
        if (conversion == 'o') base = 8;
        if (conversion == 'x' || conversion == 'X' || conversion == 'p') base = 16;
        digits = conversion == 'X' ? "0123456789ABCDEF" : "0123456789abcdef";
        if ((alternate && base == 16 && value != 0) || conversion == 'p') {
            prefix[prefix_size++] = '0';
            prefix[prefix_size++] = conversion == 'X' ? 'X' : 'x';
        }
        used = 0;
        if (value != 0 || precision != 0 || conversion == 'p') {
            do {
                number[31 - used] = digits[value % (unsigned long)base];
                used = used + 1;
                value = value / (unsigned long)base;
            } while (value != 0);
        }
        zeros = precision > used ? precision - used : 0;
        if (alternate && base == 8 && (used == 0 || number[32 - used] != '0') && zeros == 0)
            zeros = 1;
        if (zeros > INT_MAX - used - prefix_size) { seed_print_error(output, SEED_EOVERFLOW); break; }
        content = prefix_size + zeros + used;
        padding = width > content ? width - content : 0;
        if (zero && !left && precision < 0) { zeros = zeros + padding; padding = 0; }
        if (!left && !seed_print_padding(output, ' ', padding)) break;
        if (!seed_print_bytes(output, prefix, prefix_size)) break;
        if (!seed_print_padding(output, '0', zeros)) break;
        if (!seed_print_bytes(output, number + 32 - used, used)) break;
        if (left && !seed_print_padding(output, ' ', padding)) break;
    }
    return output->failed ? -1 : output->count;
}

int vfprintf(FILE *stream, const char *format, va_list arguments)
{
    struct seed_print output;
    unsigned char local[BUFSIZ + SEED_UNGET];
    int result;
    if (seed_to_write(stream)) return -1;
    output.stream = stream;
    output.buffer = NULL;
    output.capacity = 0;
    output.count = 0;
    output.failed = 0;
    if (stream->__mode != _IONBF)
        return seed_format(&output, format, arguments);
    /* Like glibc, an unbuffered stream gets one temporary buffer for the
       whole call, so a short message reaches the descriptor in one write. */
    stream->__buf = local + SEED_UNGET;
    stream->__size = BUFSIZ;
    stream->__mode = _IOFBF;
    stream->__wbase = stream->__buf;
    stream->__wpos = stream->__buf;
    stream->__wend = stream->__buf + BUFSIZ;
    result = seed_format(&output, format, arguments);
    if (seed_flush_write(stream)) result = -1;
    stream->__mode = _IONBF;
    stream->__buf = NULL;
    stream->__size = 0;
    seed_reset_buffer(stream);
    return result;
}
int fprintf(FILE *stream, const char *format, ...)
{
    va_list arguments;
    int result;
    va_start(arguments, format);
    result = vfprintf(stream, format, arguments);
    va_end(arguments);
    return result;
}
int vprintf(const char *format, va_list arguments) { return vfprintf(stdout, format, arguments); }
int printf(const char *format, ...)
{
    va_list arguments;
    int result;
    va_start(arguments, format);
    result = vfprintf(stdout, format, arguments);
    va_end(arguments);
    return result;
}
int vsnprintf(char *buffer, size_t size, const char *format, va_list arguments)
{
    struct seed_print output;
    size_t end;
    int result;
    output.stream = NULL;
    output.buffer = buffer;
    output.capacity = size;
    output.count = 0;
    output.failed = 0;
    result = seed_format(&output, format, arguments);
    if (size > 0) {
        end = (size_t)output.count;
        if (end >= size) end = size - 1;
        buffer[end] = 0;
    }
    return result;
}
int snprintf(char *buffer, size_t size, const char *format, ...)
{
    va_list arguments;
    int result;
    va_start(arguments, format);
    result = vsnprintf(buffer, size, format, arguments);
    va_end(arguments);
    return result;
}
int vsprintf(char *buffer, const char *format, va_list arguments)
{
    return vsnprintf(buffer, (size_t)-1, format, arguments);
}
int sprintf(char *buffer, const char *format, ...)
{
    va_list arguments;
    int result;
    va_start(arguments, format);
    result = vsprintf(buffer, format, arguments);
    va_end(arguments);
    return result;
}
void perror(const char *prefix)
{
    /* strerror covers every Linux errno and preserves errno itself. */
    int saved = errno;
    if (prefix != NULL && *prefix) fprintf(stderr, "%s: ", prefix);
    fprintf(stderr, "%s\n", strerror(saved));
    errno = saved;
}
