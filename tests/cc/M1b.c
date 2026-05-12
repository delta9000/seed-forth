/* M1b: many prototypes + multi-function forward calls + structured globals. */
int foo(int x);
int bar(int y);
int call_both(int a, int b);

int global_a;
int global_b;

int foo(int x) { return x + 1; }
int bar(int y) { return y * 2; }
int call_both(int a, int b) { return foo(a) + bar(b); }

int main()
{
	global_a = 10;
	global_b = 20;
	return call_both(global_a, global_b);
}
