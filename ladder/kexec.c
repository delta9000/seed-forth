/* Under K1: hand the machine to /boot/bzImage (reboot(2), LINUX_REBOOT_CMD_KEXEC). */
#include <stdio.h>
#include <unistd.h>
#include <sys/syscall.h>
int main(void)
{
    long r = syscall(SYS_reboot, 0xfee1dead, 672274793, 0x45584543, 0);
    printf("kexec: returned %ld\n", r);
    return 1;
}
