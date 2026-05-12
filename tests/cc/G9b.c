struct Cell {
    int value;
    int weight;
};

int sum_via_ptr(struct Cell* c)
{
    return c->value + c->weight;
}

int main()
{
    struct Cell c;
    c.value = 30;
    c.weight = 12;
    return sum_via_ptr(&c);
}
