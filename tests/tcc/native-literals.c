/* LP64 literal type selection, width normalization and unsigned operations. */
int main(void) {
    if (sizeof(1) != 4) return 1;
    if (sizeof(1u) != 4) return 2;
    if (sizeof(1L) != 8) return 3;
    if (sizeof(1ULL) != 8) return 4;
    if (sizeof(2147483648) != 8) return 5;
    if (sizeof(0x80000000) != 4) return 6;
    if (sizeof(037777777777) != 4) return 7;
    if (sizeof(0x100000000) != 8) return 8;
    if (0xffffffffU + 1U != 0U) return 9;
    if (0xffffffff + 1 != 0U) return 10;
    if (0xffffffffUL + 1 != 0x100000000UL) return 11;
    if (0x80000000U >> 31 != 1U) return 12;
    if (0xffffffffffffffffUL / 3UL != 0x5555555555555555UL) return 13;
    if (0xffffffffffffffffUL % 7UL != 1UL) return 14;
    if (0xffffffffffffffffUL < 1UL) return 15;
    if (0x8000000000000000UL <= 0x7fffffffffffffffUL) return 16;
    if (1UL >= 0xffffffffffffffffUL) return 17;
    if (0xffffffffU <= 1U) return 18;
    if (0xffffffffL != 4294967295L) return 19;
    if (020000000000 != 2147483648U) return 20;
    return 0;
}
