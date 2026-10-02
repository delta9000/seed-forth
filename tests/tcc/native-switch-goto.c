int f(int a) { int n=0; switch(a) { case 1: goto inner; case 2: n=5; inner: n+=7; break; default: n=9; } return n; }
int g(int a) { switch(a) { case 1: goto out; default: return 2; } out: return 3; }
int h(void) { goto in; switch(4) { case 1: return 2; in: return 4; } }
int main(void) { return f(1)+f(2)+f(3)+g(1)+g(2)+h()-37; }
