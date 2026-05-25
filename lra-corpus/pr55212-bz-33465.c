
typedef float SFtype __attribute__ ((mode (SF)));
typedef _Complex float SCtype __attribute__ ((mode (SC)));

SCtype
__divsc3 (SFtype a, SFtype b, SFtype c, SFtype d)
{
  SFtype denom, ratio, x, y;
  SCtype res;





  if (__builtin_fabsf (c) < __builtin_fabsf (d))
    {
      ratio = c / d;
      denom = (c * ratio) + d;
      x = ((a * ratio) + b) / denom;
      y = ((b * ratio) - a) / denom;
    }

  else
    {
      ratio = d / c;
      denom = (d * ratio) + c;
      x = ((b * ratio) + a) / denom;
      y = (b - (a * ratio)) / denom;
    }

  if (__builtin_expect ((x) != (x), 0) && __builtin_expect ((y) != (y), 0))
    {
      if (c == 0.0 && d == 0.0 && (!__builtin_expect ((a) != (a), 0) || !__builtin_expect ((b) != (b), 0)))
 {
   x = __builtin_copysignf (__builtin_huge_valf (), c) * a;
   y = __builtin_copysignf (__builtin_huge_valf (), c) * b;
 }
      else if ((__builtin_expect (!__builtin_expect ((a) != (a), 0) & !__builtin_expect (!__builtin_expect (((a) - (a)) != ((a) - (a)), 0), 1), 0) || __builtin_expect (!__builtin_expect ((b) != (b), 0) & !__builtin_expect (!__builtin_expect (((b) - (b)) != ((b) - (b)), 0), 1), 0)) && __builtin_expect (!__builtin_expect (((c) - (c)) != ((c) - (c)), 0), 1) && __builtin_expect (!__builtin_expect (((d) - (d)) != ((d) - (d)), 0), 1))
 {
   a = __builtin_copysignf (__builtin_expect (!__builtin_expect ((a) != (a), 0) & !__builtin_expect (!__builtin_expect (((a) - (a)) != ((a) - (a)), 0), 1), 0) ? 1 : 0, a);
   b = __builtin_copysignf (__builtin_expect (!__builtin_expect ((b) != (b), 0) & !__builtin_expect (!__builtin_expect (((b) - (b)) != ((b) - (b)), 0), 1), 0) ? 1 : 0, b);
   x = __builtin_huge_valf () * (a * c + b * d);
   y = __builtin_huge_valf () * (b * c - a * d);
 }
      else if ((__builtin_expect (!__builtin_expect ((c) != (c), 0) & !__builtin_expect (!__builtin_expect (((c) - (c)) != ((c) - (c)), 0), 1), 0) || __builtin_expect (!__builtin_expect ((d) != (d), 0) & !__builtin_expect (!__builtin_expect (((d) - (d)) != ((d) - (d)), 0), 1), 0)) && __builtin_expect (!__builtin_expect (((a) - (a)) != ((a) - (a)), 0), 1) && __builtin_expect (!__builtin_expect (((b) - (b)) != ((b) - (b)), 0), 1))
 {
   c = __builtin_copysignf (__builtin_expect (!__builtin_expect ((c) != (c), 0) & !__builtin_expect (!__builtin_expect (((c) - (c)) != ((c) - (c)), 0), 1), 0) ? 1 : 0, c);
   d = __builtin_copysignf (__builtin_expect (!__builtin_expect ((d) != (d), 0) & !__builtin_expect (!__builtin_expect (((d) - (d)) != ((d) - (d)), 0), 1), 0) ? 1 : 0, d);
   x = 0.0 * (a * c + b * d);
   y = 0.0 * (b * c - a * d);
 }
    }

  __real__ res = x;
  __imag__ res = y;
  return res;
}
