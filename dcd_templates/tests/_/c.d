//struct Fuck(A, B, C)
//{
//    A field_a;
//    B field_b;
//    C field_c;
//
//    A[] array_a;
//    B[] array_b;
//    C[] array_c;
//}
//
//struct DataA{}
//struct DataB{}
//struct DataC{}
//
//extern(C) int main()
//{
//    Fuck!(DataA, DataB, DataC) fuck;
//    //auto fuck = Fuck!(DataA, DataB);
//
//    fuck.
//}


struct Stack(T)
{
  int idx;
  T[] items;
}

enum CLIPSTACK_SIZE = 4;
struct Rect{}
struct Context
{
    Stack!(Rect) clip_stack;
}

void main()
{
    Context ctx;
    ctx.clip_stack.
}
