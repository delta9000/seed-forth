/* Direct record-array fixture isolates lowering from typedef aliases. */
struct __seed_va_list_tag {
    unsigned int gp_offset;
    unsigned int fp_offset;
    void *overflow_arg_area;
    void *reg_save_area;
};
struct __seed_va_list_tag *through(struct __seed_va_list_tag *list)
{
    return list;
}
long sum(int count, ...)
{
    struct __seed_va_list_tag list[1];
    struct __seed_va_list_tag copy[1];
    int index;
    long result = 0;
    __builtin_va_start(list, count);
    __builtin_va_copy(copy, through(list));
    for (index = 0; index < count; index = index + 1)
        result = result + __builtin_va_arg(list, long);
    __builtin_va_end(list);
    if (result != 36) return 1;
    for (index = 0; index < count; index = index + 1)
        result = result - __builtin_va_arg(copy, long);
    __builtin_va_end(copy);
    return result;
}
int main(void) { return sum(8,1L,2L,3L,4L,5L,6L,7L,8L); }
