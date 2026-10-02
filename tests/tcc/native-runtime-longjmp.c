void longjmp(int environment, int value);
int main(void) { longjmp(0, 1); return 99; }
