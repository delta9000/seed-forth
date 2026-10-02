extern int values[];
int *address(void) { return values; }
int values[] = {3,5,7};
int x = 10;
int f(void) { static int x=21; return x++; }
int main(void) { return address()[2] + values[1] + f() + f() + x - 65; }
