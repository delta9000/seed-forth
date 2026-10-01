/* /init for K1's Linux hand-off test: say hello, then leave QEMU with
 * status 42 through isa-debug-exit. */
#include <stdio.h>
#include <unistd.h>
#include <sys/io.h>
#include <sys/utsname.h>
int main(void)
{
    struct utsname u;
    uname(&u);
    printf("linit: hello from %s %s userland\n", u.sysname, u.release);
    fflush(stdout);
    if (ioperm(0xf4, 1, 1) == 0)
        outb(42, 0xf4);
    return 1;
}
