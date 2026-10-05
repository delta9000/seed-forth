/* Original seed-forth implementation; distributed under ../../LICENSE. */
#include <stdio.h>
#include <unistd.h>

void setbuf(FILE *stream, char *buffer)
{
    /* Every seed FILE is actually unbuffered. A non-NULL buffer requests
       unsupported buffering; this void interface cannot return an error.
       Fail closed immediately, without diagnostic I/O that could block or
       deliver a signal, and without changing process signal state. */
    if (buffer != NULL || fileno(stream) < 0) _exit(127);
}
