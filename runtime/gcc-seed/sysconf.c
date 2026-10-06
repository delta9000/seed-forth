/* Original seed-forth implementation; see LICENSE and SYSINFO.md.
   sysconf, pathconf and fpathconf with the answers Linux glibc gives. */
#include <unistd.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <seed-syscall.h>

#define SEED_PAGE_SIZE 4096L

static long seed_limit(int resource, int infinite_is_unlimited)
{
    struct rlimit limit;
    if (getrlimit(resource, &limit) < 0) return -1;
    if (limit.rlim_cur == RLIM_INFINITY && infinite_is_unlimited) return -1;
    return (long)limit.rlim_cur;
}

/* Read a small kernel text file into BUFFER (NUL-terminated); -1 on error. */
static long seed_read_text(const char *path, char *buffer, long size)
{
    long descriptor, done = 0, count;
    descriptor = __seed_syscall6(2, (long)path, O_RDONLY | O_CLOEXEC, 0, 0, 0, 0);
    if (descriptor < 0) return -1;
    while (done < size - 1) {
        count = __seed_syscall6(0, descriptor, (long)(buffer + done), size - 1 - done, 0, 0, 0);
        if (count == -EINTR) continue;
        if (count <= 0) break;
        done += count;
    }
    __seed_syscall6(3, descriptor, 0, 0, 0, 0, 0);
    buffer[done] = '\0';
    return done;
}

/* Count CPUs in a kernel list such as "0-3,8,10-11". */
static long seed_cpu_list(const char *path)
{
    char text[1024];
    char *cursor;
    long first, last, total = 0;
    if (seed_read_text(path, text, sizeof(text)) <= 0) return -1;
    cursor = text;
    while (*cursor >= '0' && *cursor <= '9') {
        first = strtol(cursor, &cursor, 10);
        last = first;
        if (*cursor == '-') last = strtol(cursor + 1, &cursor, 10);
        if (last >= first) total += last - first + 1;
        if (*cursor != ',') break;
        cursor++;
    }
    return total > 0 ? total : -1;
}

static long seed_affinity_count(void)
{
    unsigned long mask[16];
    long bytes, index, total = 0;
    unsigned long word;
    bytes = __seed_syscall6(204, 0, sizeof(mask), (long)mask, 0, 0, 0);
    if (bytes <= 0) return 1;
    for (index = 0; index < bytes / 8; index++)
        for (word = mask[index]; word; word &= word - 1) total++;
    return total ? total : 1;
}

static long seed_memory_pages(int available)
{
    long information[16];
    unsigned long amount;
    unsigned int unit;
    memset(information, 0, sizeof(information));
    if (__seed_syscall6(99, (long)information, 0, 0, 0, 0, 0) < 0) return -1;
    amount = (unsigned long)information[available ? 5 : 4];
    memcpy(&unit, (char *)information + 104, sizeof(unit));
    if (unit == 0) unit = 1;
    return (long)(amount / ((unsigned long)SEED_PAGE_SIZE / unit));
}

long sysconf(int name)
{
    long value;
    switch (name) {
    case _SC_ARG_MAX:
        /* The kernel allows a quarter of the stack limit for arguments. */
        value = seed_limit(RLIMIT_STACK, 0);
        if (value < 0) return 131072;
        value = (long)((unsigned long)value / 4);
        return value > 131072 ? value : 131072;
    case _SC_CHILD_MAX: return seed_limit(RLIMIT_NPROC, 1);
    case _SC_CLK_TCK: return 100;
    case _SC_NGROUPS_MAX: return 65536;
    case _SC_OPEN_MAX: return seed_limit(RLIMIT_NOFILE, 0);
    case _SC_STREAM_MAX: return 16;
    case _SC_TZNAME_MAX: return -1;
    case _SC_JOB_CONTROL: return 1;
    case _SC_SAVED_IDS: return 1;
    case _SC_VERSION: return 200809L;
    case _SC_PAGESIZE: return SEED_PAGE_SIZE;
    case _SC_RTSIG_MAX: return 32;
    case _SC_BC_BASE_MAX: return 99;
    case _SC_BC_DIM_MAX: return 2048;
    case _SC_BC_SCALE_MAX: return 99;
    case _SC_BC_STRING_MAX: return 1000;
    case _SC_COLL_WEIGHTS_MAX: return 255;
    case _SC_EXPR_NEST_MAX: return 32;
    case _SC_LINE_MAX: return 2048;
    case _SC_RE_DUP_MAX: return 32767;
    case _SC_2_VERSION: return 200809L;
    case _SC_IOV_MAX: return 1024;
    case _SC_GETGR_R_SIZE_MAX: return 1024;
    case _SC_GETPW_R_SIZE_MAX: return 1024;
    case _SC_LOGIN_NAME_MAX: return 256;
    case _SC_TTY_NAME_MAX: return 32;
    case _SC_NPROCESSORS_CONF:
        value = seed_cpu_list("/sys/devices/system/cpu/possible");
        return value > 0 ? value : seed_affinity_count();
    case _SC_NPROCESSORS_ONLN:
        value = seed_cpu_list("/sys/devices/system/cpu/online");
        return value > 0 ? value : seed_affinity_count();
    case _SC_PHYS_PAGES: return seed_memory_pages(0);
    case _SC_AVPHYS_PAGES: return seed_memory_pages(1);
    case _SC_SYMLOOP_MAX: return -1;
    case _SC_HOST_NAME_MAX: return 64;
    }
    errno = EINVAL;
    return -1;
}

int getpagesize(void)
{
    return (int)SEED_PAGE_SIZE;
}

int getdtablesize(void)
{
    long value = seed_limit(RLIMIT_NOFILE, 0);
    return value < 0 || value > 2147483647L ? 256 : (int)value;
}

/* Linux statfs magic numbers with link-count or file-size limits that
   differ from the defaults (glibc's tables for these file systems). */
#define SEED_EXT_MAGIC 0xEF53L
#define SEED_XFS_MAGIC 0x58465342L
#define SEED_BTRFS_MAGIC 0x9123683EL
#define SEED_REISERFS_MAGIC 0x52654973L
#define SEED_UFS_MAGIC 0x00011954L
#define SEED_MINIX_MAGIC 0x137FL
#define SEED_MINIX_MAGIC2 0x138FL
#define SEED_MINIX2_MAGIC 0x2468L
#define SEED_MINIX2_MAGIC2 0x2478L

/* ext2/ext3 allow 32000 links and ext4 65000; they share one magic number,
   so look up the mounted type of DEVICE in /proc/self/mountinfo. */
static long seed_ext_link_max(dev_t device)
{
    char *text = NULL, *line, *next, *field, *separator;
    long size = 0, used = 0, count, descriptor;
    unsigned long high, low;
    long result = 32000;
    descriptor = __seed_syscall6(2, (long)"/proc/self/mountinfo", O_RDONLY | O_CLOEXEC, 0, 0, 0, 0);
    if (descriptor < 0) return result;
    for (;;) {
        if (used + 4097 > size) {
            char *grown = realloc(text, (size_t)(size + 65536));
            if (grown == NULL) break;
            text = grown;
            size += 65536;
        }
        count = __seed_syscall6(0, descriptor, (long)(text + used), 4096, 0, 0, 0);
        if (count == -EINTR) continue;
        if (count <= 0) break;
        used += count;
    }
    __seed_syscall6(3, descriptor, 0, 0, 0, 0, 0);
    if (text == NULL) return result;
    text[used] = '\0';
    for (line = text; *line; line = next) {
        next = strchr(line, '\n');
        if (next) *next++ = '\0'; else next = line + strlen(line);
        /* Fields: id, parent id, major:minor, ... " - " fstype source. */
        field = strchr(line, ' ');
        if (field == NULL || (field = strchr(field + 1, ' ')) == NULL) continue;
        high = strtoul(field + 1, &field, 10);
        if (*field != ':') continue;
        low = strtoul(field + 1, &field, 10);
        if (makedev(high, low) != device) continue;
        separator = strstr(field, " - ");
        if (separator == NULL) continue;
        if (strncmp(separator + 3, "ext4 ", 5) == 0) result = 65000;
        break;
    }
    free(text);
    return result;
}

static long seed_pathconf(long kind, long target, int name)
{
    long information[16];
    struct stat status;
    long result;
    switch (name) {
    case _PC_MAX_CANON: return 255;
    case _PC_MAX_INPUT: return 255;
    case _PC_PATH_MAX: return 4096;
    case _PC_PIPE_BUF: return 4096;
    case _PC_CHOWN_RESTRICTED: return 1;
    case _PC_NO_TRUNC: return 1;
    case _PC_VDISABLE: return 0;
    case _PC_SYMLINK_MAX: return -1;
    case _PC_2_SYMLINKS: return 1;
    case _PC_LINK_MAX:
    case _PC_NAME_MAX:
    case _PC_FILESIZEBITS:
        break;
    default:
        errno = EINVAL;
        return -1;
    }
    /* statfs (137) or fstatfs (138): f_type is word 0, f_namelen word 8. */
    result = __seed_syscall6(kind, target, (long)information, 0, 0, 0, 0);
    if (result < 0) { errno = (int)-result; return -1; }
    if (name == _PC_NAME_MAX) return information[8];
    if (name == _PC_FILESIZEBITS) {
        if (information[0] == SEED_BTRFS_MAGIC) return 255;
        if (information[0] == SEED_EXT_MAGIC || information[0] == SEED_XFS_MAGIC
            || information[0] == SEED_UFS_MAGIC) return 64;
        return 32;
    }
    switch (information[0]) {
    case SEED_EXT_MAGIC:
        result = kind == 137 ? stat((const char *)target, &status) : fstat((int)target, &status);
        return result < 0 ? 32000 : seed_ext_link_max(status.st_dev);
    case SEED_XFS_MAGIC: return 2147483647L;
    case SEED_BTRFS_MAGIC: return 65535;
    case SEED_REISERFS_MAGIC: return 64535;
    case SEED_UFS_MAGIC: return 32000;
    case SEED_MINIX_MAGIC: case SEED_MINIX_MAGIC2: return 250;
    case SEED_MINIX2_MAGIC: case SEED_MINIX2_MAGIC2: return 65530;
    }
    return 127;
}

long pathconf(const char *path, int name)
{
    return seed_pathconf(137, (long)path, name);
}

long fpathconf(int descriptor, int name)
{
    return seed_pathconf(138, descriptor, name);
}
