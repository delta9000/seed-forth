#ifndef SEED_GCC_STDARG_H
#define SEED_GCC_STDARG_H
/* System V AMD64 va_list. Array identity is part of the ABI: a parameter
   declared va_list adjusts to a pointer to this record, not a record copy. */
typedef struct __seed_va_list_tag {
    unsigned int gp_offset;
    unsigned int fp_offset;
    void *overflow_arg_area;
    void *reg_save_area;
} __builtin_va_list[1];
typedef __builtin_va_list __gnuc_va_list;
typedef __builtin_va_list va_list;
#define va_start(list, last) __builtin_va_start((list), last)
#define va_arg(list, type) __builtin_va_arg((list), type)
#define va_copy(destination, source) __builtin_va_copy((destination), (source))
#define __va_copy(destination, source) __builtin_va_copy((destination), (source))
#define va_end(list) __builtin_va_end((list))
#endif
