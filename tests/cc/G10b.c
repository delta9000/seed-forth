typedef int my_int;
typedef int* int_ptr;

int main()
{
    my_int x = 7;
    int_ptr p = &x;
    *p = 42;
    return x;
}
