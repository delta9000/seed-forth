#ifndef SEED_GCC_DIRECTORY_H
#define SEED_GCC_DIRECTORY_H
/* Private DIR record shared by dirent.c and dirfd.c; not a public layout.
   A long array gives every kernel record its required eight-byte alignment. */
struct seed_directory {
    int descriptor;
    int ended;
    unsigned long position;
    unsigned long available;
    long buffer[4096];
};
#endif
