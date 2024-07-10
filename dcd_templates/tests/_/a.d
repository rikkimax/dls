struct Fuck(A, B, C)
{
    A a;
    B b;
    C c;
}

void main()
{
    Fuck!(DataA, DataB, Fuck!(DataB, Fuck!(DataB, DataC, DataA), DataA)) fuck;
    fuck.c.
    // 113
}

struct Data
{
    int it;
    Data* data;
}

struct DataA
{
    int aaa;
    Data* data;
}
struct DataB
{
    int bbb;
    Data* data;
}
struct DataC
{
    int ccc;
    Data* data;
}
