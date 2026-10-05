/* Pending composition witness: also requires the ranked-array repair. */
static int read_ranked(int (*array)[2][3][4]) { return array[1][1][2][3]; }
static int apply(int callback(int (*)[2][3][4]), int (*array)[2][3][4])
{ return callback(array); }
int main(void)
{
    int data[2][2][3][4];
    int (*pointer)(int (*)[2][3][4]) = read_ranked;
    data[1][1][2][3]=79;
    return apply(pointer,data)!=79;
}
