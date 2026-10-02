/* Array parameter decay and mixed-width values all use eight-byte slots. */
long slots(char a, short b, unsigned int c, long d,
           int values[], int count, char *text, unsigned long wide) {
    if (a != -3 || b != -257 || c != 4294967295U) return 1;
    if (d != 4294967301L || wide != 0xfedcba9876543210UL) return 2;
    if (count != 3 || values[0] != 11 || values[2] != 33) return 3;
    if (text[0] != 'o' || text[1] != 'k') return 4;
    values[1] = 44;
    return 0;
}
int main(void) {
    int values[3];
    long result;
    values[0] = 11;
    values[1] = 22;
    values[2] = 33;
    result = slots((char)-3, (short)-257, 4294967295U, 4294967301L,
                   values, 3, "ok", 0xfedcba9876543210UL);
    if (result != 0) return result;
    return values[1] != 44;
}
