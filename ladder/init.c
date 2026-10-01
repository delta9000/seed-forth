/* ladder/init.c: PID 1 of the initramfs the ladder's Linux boots.
 *
 * Mounts /proc, prints the kernel's own version line (which names the
 * compiler that built it), then exits QEMU through the isa-debug-exit
 * device at port 0xf4 with status 42, so QEMU's exit code (42*2+1 = 85)
 * says the chain-built kernel booted and ran a chain-built program.
 */
#include <fcntl.h>
#include <stdio.h>
#include <sys/io.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <unistd.h>

int main(void) {
    char buf[512];
    int fd;
    ssize_t n;
    mount("proc", "/proc", "proc", 0, 0);
    printf("init: hello from a Linux kernel built from hex0 and seed-forth\n");
    fd = open("/proc/version", O_RDONLY);
    if (fd >= 0) {
        n = read(fd, buf, sizeof buf - 1);
        if (n > 0) {
            buf[n] = 0;
            printf("init: %s", buf);
        }
        close(fd);
    }
    fflush(stdout);
    if (ioperm(0xf4, 1, 1) == 0)
        outb(42, 0xf4);                 /* isa-debug-exit: QEMU exits 85 */
    reboot(RB_POWER_OFF);
    for (;;)
        pause();
}
