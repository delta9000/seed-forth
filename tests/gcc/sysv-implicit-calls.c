/* C90 implicit externs keep block visibility and translation-unit identity. */
struct add { int add; };
int call_before_definition(void) {
    int result;
    signed char narrow;
    narrow = -3;
    { result = add(narrow, 15); }
    { result = result + add(13, 17); }
    return result;
}
int scoped_function_value(void) {
    int (*fp)(int, int);
    add(0, 0);
    fp = add;
    return fp(20, 22);
}
int add(int a, int b) { return a + b; }
int main(void) {
    if (call_before_definition() != 42) return 1;
    if (scoped_function_value() != 42) return 2;
    return 0;
}
