#ifndef SEED_GCC_SYS_MTIO_H
#define SEED_GCC_SYS_MTIO_H
/* Original seed-forth interface; see LICENSE and ../../TERMIOS.md.
   Linux AMD64 magnetic-tape ioctl records and request numbers only;
   use them with ioctl from <sys/ioctl.h>. */
struct mtop {
    short mt_op;
    int mt_count;
};
struct mtget {
    long mt_type;
    long mt_resid;
    long mt_dsreg;
    long mt_gstat;
    long mt_erreg;
    int mt_fileno;
    int mt_blkno;
};
struct mtpos {
    long mt_blkno;
};
#define MTIOCTOP 0x40086d01UL
#define MTIOCGET 0x80306d02UL
#define MTIOCPOS 0x80086d03UL
#define MTRESET 0
#define MTFSF 1
#define MTBSF 2
#define MTFSR 3
#define MTBSR 4
#define MTWEOF 5
#define MTREW 6
#define MTOFFL 7
#define MTNOP 8
#define MTRETEN 9
#define MTBSFM 10
#define MTFSFM 11
#define MTEOM 12
#define MTERASE 13
#endif
