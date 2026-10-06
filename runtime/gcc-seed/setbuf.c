/* Original seed-forth implementation; distributed under ../../LICENSE.
   See DIRECTORY-BUFFERING.md. */
#include <stdio.h>
#include <unistd.h>
#include <errno.h>

int setvbuf(FILE *stream, char *buffer, int mode, size_t size)
{
    /* Every seed FILE is unbuffered and stays so: a requested buffer is
       neither read nor retained, and a valid request simply succeeds. */
    (void)buffer;
    (void)size;
    if (fileno(stream) < 0) return EOF;
    if (mode != _IOFBF && mode != _IOLBF && mode != _IONBF) {
        errno = EINVAL;
        return EOF;
    }
    return 0;
}

void setbuf(FILE *stream, char *buffer)
{
    /* NULL or a closed stream is outside the live-object contract; fail
       closed without diagnostic I/O, as before. Any buffer is accepted. */
    (void)buffer;
    if (fileno(stream) < 0) _exit(127);
}
