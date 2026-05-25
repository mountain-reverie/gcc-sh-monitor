typedef struct { int c[64]; } obj;

extern void bar (int, int, int, int, obj *);
void foo (obj *p)
{
  obj bobj = *p;
  bar (0, 0, 0, 0, &bobj);
}
