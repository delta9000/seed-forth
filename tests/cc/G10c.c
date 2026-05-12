struct Pair {
    int a;
    int b;
};

int main()
{
    int x;
    int* p;
    int arr[7];
    struct Pair pp;
    int sum = 0;
    sum = sum + sizeof(x);
    sum = sum + sizeof(p);
    sum = sum + sizeof(arr);
    sum = sum + sizeof(struct Pair);
    sum = sum + sizeof(int);
    return sum;
}
