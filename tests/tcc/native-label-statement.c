int f(int x) { if (x==3) bad: return 7; if(x==4) goto bad; return 0; }
int main(void) { return f(0)+f(3)+f(4)-14; }
