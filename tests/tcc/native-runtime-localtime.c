struct tm { int seconds; };
struct tm *localtime(const long *value);
int main(void) { localtime((long *)0); return 99; }
