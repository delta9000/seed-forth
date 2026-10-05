/* Original seed-forth implementation; distributed under ../../LICENSE.
   Unbuffered Linux AMD64 streams and bounded integer/pointer formatting. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <errno.h>
#include <seed-syscall.h>
#include <fcntl.h>
#include <wchar.h>

#define SEED_READ 1
#define SEED_WRITE 2
#define SEED_OWNED 4
#define SEED_EOVERFLOW 75

struct __seed_FILE {
    int descriptor;
    int flags;
    int error;
    int ended;
    int pushed;
    unsigned char byte;
};

static FILE seed_input;
static FILE seed_output;
static FILE seed_error;
static int seed_streams_ready;

static void seed_streams_init(void)
{
    if (!seed_streams_ready) {
        seed_input.descriptor = 0;
        seed_input.flags = SEED_READ;
        seed_output.descriptor = 1;
        seed_output.flags = SEED_WRITE;
        seed_error.descriptor = 2;
        seed_error.flags = SEED_WRITE;
        seed_streams_ready = 1;
    }
}

FILE *__seed_stdin(void) { seed_streams_init(); return &seed_input; }
FILE *__seed_stdout(void) { seed_streams_init(); return &seed_output; }
FILE *__seed_stderr(void) { seed_streams_init(); return &seed_error; }

static int seed_stream_check(FILE *stream, int access)
{
    if (stream == NULL || stream->descriptor < 0 || !(stream->flags & access)) {
        errno = EBADF;
        if (stream != NULL) stream->error = 1;
        return 0;
    }
    return 1;
}

static int seed_open_mode(const char *mode, int *flags, int *access)
{
    int binary = 0;
    int update = 0;
    int index = 1;
    if (mode == NULL) { errno = EINVAL; return 0; }
    if (mode[0] == 'r') { *flags = O_RDONLY; *access = SEED_READ; }
    else if (mode[0] == 'w') { *flags = O_WRONLY | O_CREAT | O_TRUNC; *access = SEED_WRITE; }
    else if (mode[0] == 'a') { *flags = O_WRONLY | O_CREAT | O_APPEND; *access = SEED_WRITE; }
    else { errno = EINVAL; return 0; }
    while (mode[index]) {
        if (mode[index] == '+' && !update) update = 1;
        else if (mode[index] == 'b' && !binary) binary = 1;
        else { errno = EINVAL; return 0; }
        index++;
    }
    if (update) {
        *flags = (*flags & ~O_ACCMODE) | O_RDWR;
        *access = SEED_READ | SEED_WRITE;
    }
    return 1;
}

static void seed_stream_init(FILE *stream, int descriptor, int access)
{
    stream->descriptor = descriptor;
    stream->flags = access | SEED_OWNED;
    stream->error = 0;
    stream->ended = 0;
    stream->pushed = 0;
    stream->byte = 0;
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
    do {
        descriptor = __seed_syscall6(2, (long)path, flags, 0666, 0, 0, 0);
    } while (descriptor == -EINTR);
    if (descriptor < 0) {
        errno = (int)-descriptor;
        free(stream);
        return NULL;
    }
    seed_stream_init(stream, (int)descriptor, access);
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
    do {
        actual_flags = __seed_syscall6(72, descriptor, F_GETFL, 0, 0, 0, 0);
    } while (actual_flags == -EINTR);
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
        do {
            result = __seed_syscall6(72, descriptor, F_SETFL,
                                    actual_flags | O_APPEND, 0, 0, 0);
        } while (result == -EINTR);
        if (result < 0) {
            errno = (int)-result;
            free(stream);
            return NULL;
        }
    }
    seed_stream_init(stream, descriptor, access);
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
    if (!seed_open_mode(mode, &flags, &access)) return NULL;
    if (!seed_stream_check(stream, SEED_READ | SEED_WRITE)) return NULL;
    previous = stream->descriptor;
    owned = stream->flags & SEED_OWNED;
    /* The stream is unbuffered. Linux close releases the descriptor even
       on EINTR; freopen ignores close errors and never retries close. */
    __seed_syscall6(3, previous, 0, 0, 0, 0, 0);
    stream->descriptor = -1;
    stream->flags = 0;
    stream->error = 0;
    stream->ended = 0;
    stream->pushed = 0;
    descriptor = -EINVAL;
    /* No filename-null mode changes are supported by this implementation. */
    if (path != NULL) {
        do {
            descriptor = __seed_syscall6(2, (long)path, flags, 0666, 0, 0, 0);
        } while (descriptor == -EINTR);
    }
    if (descriptor >= 0 && descriptor != previous) {
        do {
            result = __seed_syscall6(33, descriptor, previous, 0, 0, 0, 0);
        } while (result == -EINTR);
        __seed_syscall6(3, descriptor, 0, 0, 0, 0, 0);
        descriptor = result;
    }
    if (descriptor < 0) {
        error = (int)-descriptor;
        if (owned) free(stream);
        errno = error;
        return NULL;
    }
    seed_stream_init(stream, (int)descriptor, access);
    stream->flags = access | owned;
    return stream;
}

int fclose(FILE *stream)
{
    long result;
    int owned;
    if (!seed_stream_check(stream, SEED_READ | SEED_WRITE)) return EOF;
    owned = stream->flags & SEED_OWNED;
    /* Linux releases the descriptor even when close reports EINTR. Retrying
       could close an unrelated descriptor that reused the same number. */
    result = __seed_syscall6(3, stream->descriptor, 0, 0, 0, 0, 0);
    stream->descriptor = -1;
    stream->flags = 0;
    if (owned) free(stream);
    if (result < 0) { errno = (int)-result; return EOF; }
    return 0;
}

int fflush(FILE *stream)
{
    long result;
    if (stream == NULL) return 0;
    if (!seed_stream_check(stream, SEED_READ | SEED_WRITE)) return EOF;
    /* Writes have already reached the kernel. For readable seekable streams,
       synchronize the one byte of pushback with the underlying file offset. */
    if (stream->pushed) {
        do {
            result = __seed_syscall6(8, stream->descriptor, -1, 1, 0, 0, 0);
        } while (result == -EINTR);
        if (result < 0) { errno = (int)-result; stream->error = 1; return EOF; }
        stream->pushed = 0;
    }
    return 0;
}

int ferror(FILE *stream) { return stream->error != 0; }
int feof(FILE *stream) { return stream->ended != 0; }
void clearerr(FILE *stream) { stream->error = 0; stream->ended = 0; }

static size_t seed_write(FILE *stream, const char *data, size_t size)
{
    size_t done = 0;
    size_t part;
    long result;
    if (!seed_stream_check(stream, SEED_WRITE)) return 0;
    while (done < size) {
        part = size - done;
        if (part > 2147479552UL) part = 2147479552UL;
        result = __seed_syscall6(1, stream->descriptor, (long)(data + done),
                                 (long)part, 0, 0, 0);
        if (result == -EINTR) continue;
        if (result <= 0) {
            errno = result < 0 ? (int)-result : EIO;
            stream->error = 1;
            break;
        }
        done = done + (size_t)result;
    }
    return done;
}

size_t fwrite(const void *data, size_t size, size_t count, FILE *stream)
{
    if (size == 0 || count == 0) return 0;
    if (count > (size_t)-1 / size) {
        errno = SEED_EOVERFLOW;
        stream->error = 1;
        return 0;
    }
    return seed_write(stream, data, size * count) / size;
}

size_t fread(void *data, size_t size, size_t count, FILE *stream)
{
    char *destination = data;
    size_t total;
    size_t done = 0;
    size_t part;
    long result;
    if (size == 0 || count == 0) return 0;
    if (!seed_stream_check(stream, SEED_READ)) return 0;
    if (count > (size_t)-1 / size) {
        errno = SEED_EOVERFLOW;
        stream->error = 1;
        return 0;
    }
    total = size * count;
    if (stream->pushed) {
        destination[0] = stream->byte;
        stream->pushed = 0;
        done = 1;
    }
    while (done < total && !stream->ended) {
        part = total - done;
        if (part > 2147479552UL) part = 2147479552UL;
        result = __seed_syscall6(0, stream->descriptor, (long)(destination + done),
                                 (long)part, 0, 0, 0);
        if (result == -EINTR) continue;
        if (result < 0) { errno = (int)-result; stream->error = 1; break; }
        if (result == 0) { stream->ended = 1; break; }
        done = done + (size_t)result;
    }
    return done / size;
}

int fputc(int byte, FILE *stream)
{
    unsigned char value = (unsigned char)byte;
    if (seed_write(stream, (const char *)&value, 1) != 1) return EOF;
    return value;
}
int putc(int byte, FILE *stream) { return fputc(byte, stream); }
int putchar(int byte) { return fputc(byte, stdout); }
int fputs(const char *text, FILE *stream)
{
    size_t size = strlen(text);
    if (!seed_stream_check(stream, SEED_WRITE)) return EOF;
    return seed_write(stream, text, size) == size ? 0 : EOF;
}
int puts(const char *text)
{
    if (fputs(text, stdout) == EOF) return EOF;
    return fputc('\n', stdout) == EOF ? EOF : 0;
}
int fgetc(FILE *stream)
{
    unsigned char value;
    if (fread(&value, 1, 1, stream) != 1) return EOF;
    return value;
}
int getc(FILE *stream) { return fgetc(stream); }
int getchar(void) { return fgetc(stdin); }
char *fgets(char *buffer, int count, FILE *stream)
{
    int used = 0;
    int byte;
    int previous_error;
    int failed;
    if (count <= 0) { errno = EINVAL; return NULL; }
    if (!seed_stream_check(stream, SEED_READ)) return NULL;
    if (count == 1) { buffer[0] = 0; return buffer; }
    /* Distinguish a new read failure from a previously sticky indicator. */
    previous_error = stream->error;
    stream->error = 0;
    while (used < count - 1) {
        byte = fgetc(stream);
        if (byte == EOF) break;
        buffer[used++] = (char)byte;
        if (byte == '\n') break;
    }
    failed = stream->error;
    stream->error = previous_error || failed;
    if (failed || used == 0) return NULL;
    buffer[used] = 0;
    return buffer;
}
int ungetc(int byte, FILE *stream)
{
    if (byte == EOF) return EOF;
    if (!seed_stream_check(stream, SEED_READ) || stream->pushed) return EOF;
    stream->byte = (unsigned char)byte;
    stream->pushed = 1;
    stream->ended = 0;
    return stream->byte;
}
long ftell(FILE *stream)
{
    long result;
    if (!seed_stream_check(stream, SEED_READ | SEED_WRITE)) return -1;
    do {
        result = __seed_syscall6(8, stream->descriptor, 0, 1, 0, 0, 0);
    } while (result == -EINTR);
    if (result < 0) { errno = (int)-result; return -1; }
    return result - stream->pushed;
}

int fseek(FILE *stream, long offset, int whence)
{
    long result;
    if (!seed_stream_check(stream, SEED_READ | SEED_WRITE)) return -1;
    if (whence != SEEK_SET && whence != SEEK_CUR && whence != SEEK_END) {
        errno = EINVAL;
        return -1;
    }
    if (whence == SEEK_CUR && stream->pushed) {
        if (offset == LONG_MIN) { errno = EOVERFLOW; return -1; }
        offset--;
    }
    do {
        result = __seed_syscall6(8, stream->descriptor, offset, whence, 0, 0, 0);
    } while (result == -EINTR);
    if (result < 0) { errno = (int)-result; return -1; }
    stream->pushed = 0;
    stream->ended = 0;
    return 0;
}

void rewind(FILE *stream)
{
    /* A failed seek keeps its errno; both indicators are cleared anyway. */
    (void)fseek(stream, 0L, SEEK_SET);
    if (stream != NULL) clearerr(stream);
}

int fileno(FILE *stream)
{
    if (stream == NULL || stream->descriptor < 0) { errno = EBADF; return -1; }
    return stream->descriptor;
}

wint_t getwc(FILE *stream)
{
    int byte = fgetc(stream);
    if (byte == EOF) return WEOF;
    if (byte > 127) {
        errno = EILSEQ;
        stream->error = 1;
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
        if (seed_write(output->stream, text, size) != size) {
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
    if (!seed_stream_check(stream, SEED_WRITE)) return -1;
    output.stream = stream;
    output.buffer = NULL;
    output.capacity = 0;
    output.count = 0;
    output.failed = 0;
    return seed_format(&output, format, arguments);
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
    int saved = errno;
    const char *message = NULL;
    if (saved == 0) message = "Success";
    else if (saved == ENOENT) message = "No such file or directory";
    else if (saved == EACCES) message = "Permission denied";
    else if (saved == ENOMEM) message = "Cannot allocate memory";
    else if (saved == EMFILE) message = "Too many open files";
    else if (saved == ENFILE) message = "Too many open files in system";
    else if (saved == EIO) message = "Input/output error";
    else if (saved == EBADF) message = "Bad file descriptor";
    else if (saved == EINVAL) message = "Invalid argument";
    else if (saved == EINTR) message = "Interrupted system call";
    else if (saved == EEXIST) message = "File exists";
    else if (saved == ENOTDIR) message = "Not a directory";
    else if (saved == EISDIR) message = "Is a directory";
    else if (saved == ENAMETOOLONG) message = "File name too long";
    else if (saved == ELOOP) message = "Too many levels of symbolic links";
    else if (saved == ENOSPC) message = "No space left on device";
    else if (saved == EPIPE) message = "Broken pipe";
    if (prefix != NULL && *prefix) fprintf(stderr, "%s: ", prefix);
    if (message != NULL) fprintf(stderr, "%s\n", message);
    else fprintf(stderr, "Unknown error %d\n", saved);
    errno = saved;
}
