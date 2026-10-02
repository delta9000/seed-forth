#define PNUT_CC 1
#define PNUT_EXE 1
#define PNUT_EXE_64 1
#define PNUT_X86_64 1
#define PNUT_X86_64_LINUX 1
#define __linux__ 1
#define __x86_64__ 1
#define BOOTSTRAP 1
#define HAVE_LONG_LONG 1
#define TCC_TARGET_X86_64 1
#define CONFIG_SYSROOT "/"
#define CONFIG_TCC_CRTPREFIX "build/boot0-lib"
#define CONFIG_TCC_ELFINTERP "/mes/loader"
#define CONFIG_TCC_SYSINCLUDEPATHS "libc64/include"
#define TCC_LIBGCC "build/boot0-lib/libc.a"
#define CONFIG_TCC_LIBTCC1_MES 0
#define CONFIG_TCCBOOT 1
#define CONFIG_TCC_STATIC 1
#define CONFIG_USE_LIBGCC 1
#define TCC_VERSION "0.9.27"
#define ONE_SOURCE 1
#define CONFIG_TCCDIR "build/boot0-lib/tcc"
#define __intptr_t_defined 1
#include "libc64/libc.c"
#include "tcc-0.9.27/tcc.c"
