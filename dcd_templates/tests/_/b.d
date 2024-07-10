struct Fuck(A, B, C)
{
    A a;
    B b;
    C c;
}

void main()
{
    auto fuck = Fuck!(DataA, DataB, DataC);
    fuck.
    // 120
}

struct Data
{
    int a;
    Data* data;
}

struct DataA
{
    int a;
    Data* data;
}
struct DataB
{
    int a;
    Data* data;
}
struct DataC
{
    int a;
    Data* data;
}
