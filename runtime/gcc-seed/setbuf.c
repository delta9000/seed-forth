/* Original seed-forth implementation; distributed under ../../LICENSE. */
#include <stdio.h>

void setbuf(FILE *stream, char *buffer)
{
    /* C: equivalent to setvbuf with BUFSIZ, or unbuffered for NULL. */
    setvbuf(stream, buffer, buffer ? _IOFBF : _IONBF, BUFSIZ);
}
