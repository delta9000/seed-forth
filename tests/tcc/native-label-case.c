int f(int x) { int n=9; switch(x) { case 1: goto shared; shared: default: n=4; break; } return n; }
int main(void) { int x=7; switch(1) {case 1: {int x=11; if(x!=11)return 1;} break;} return f(1)+f(3)+x-15; }
