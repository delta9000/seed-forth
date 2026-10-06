#ifndef SEED_GCC_SYS_SYSMACROS_H
#define SEED_GCC_SYS_SYSMACROS_H
/* Original seed-forth interface; see ../../FILE-CALLS.md. The Linux 64-bit
   dev_t encoding: major in bits 8-19 and 32-63, minor in bits 0-7 and 20-31
   (glibc's layout). Each macro evaluates its arguments once. */
#define major(device) ((unsigned int)((((unsigned long)(device) >> 8) & 0xfffUL) \
                                      | (((unsigned long)(device) >> 32) & 0xfffff000UL)))
#define minor(device) ((unsigned int)(((unsigned long)(device) & 0xffUL) \
                                      | (((unsigned long)(device) >> 12) & 0xffffff00UL)))
#define makedev(high, low) __seed_makedev((unsigned int)(high), (unsigned int)(low))
unsigned long __seed_makedev(unsigned int high, unsigned int low);
#endif
