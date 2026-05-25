typedef unsigned int uintptr_t;
typedef unsigned int size_t;
typedef struct {
}
  __sigset_t;
typedef unsigned long int pthread_t;
extern void free (void *__ptr) __attribute__ ((__nothrow__));
extern void *gomp_malloc (size_t) __attribute__((malloc));
				  extern void *gomp_realloc (void *, size_t);
				  extern void gomp_fatal (const char *, ...) __attribute__ ((noreturn, format (printf, 1, 2)));
				  struct gomp_team_state {
				    struct gomp_team *team;
				    unsigned team_id;
				    unsigned level;
				  };
struct gomp_team {
  unsigned nthreads;
  struct gomp_team_state prev_ts;
};
extern void gomp_display_string (char *, size_t, size_t *, const char *, size_t);
typedef pthread_t gomp_thread_handle;
typedef enum omp_alloctrait_value_t {
  omp_atv_default = (unsigned int) -1, omp_atv_false = 0, omp_atv_true = 1, omp_atv_contended = 3, omp_atv_uncontended = 4, omp_atv_serialized = 5, omp_atv_sequential = omp_atv_serialized, omp_atv_private = 6, omp_atv_all = 7, omp_atv_thread = 8, omp_atv_pteam = 9, omp_atv_cgroup = 10, omp_atv_default_mem_fb = 11, omp_atv_null_fb = 12, omp_atv_abort_fb = 13, omp_atv_allocator_fb = 14, omp_atv_environment = 15, omp_atv_nearest = 16, omp_atv_blocked = 17, omp_atv_interleaved = 18 }
  omp_event_handle_t;
extern int omp_get_num_teams (void) __attribute__((__nothrow__));
extern int omp_get_team_num (void) __attribute__((__nothrow__));
extern size_t strlen (__const char *__s) __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));
typedef struct {
}
  __attribute__ ((__packed__)) __STRING2_COPY_ARR7;
extern void *__rawmemchr (const void *__s, int __c);
extern int sprintf (char *__restrict __s, __const char *__restrict __format, ...) __attribute__ ((__nothrow__));
extern int gethostname (char *__name, size_t __len) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
static void gomp_display_repeat (char *buffer, size_t size, size_t *ret, char c, size_t len) {
}
static void gomp_display_num (char *buffer, size_t size, size_t *ret, _Bool zero, _Bool right, size_t sz, char *buf) {
  size_t l = strlen (buf);
  if (sz == (size_t) -1 || l >= sz) {
    gomp_display_string (buffer, size, ret, buf, l);
  }
}
static void gomp_display_int (char *buffer, size_t size, size_t *ret, _Bool zero, _Bool right, size_t sz, int num) {
  char buf[3 * sizeof (int) + 2];
  gomp_display_num (buffer, size, ret, zero, right, sz, buf);
}
static void gomp_display_string_len (char *buffer, size_t size, size_t *ret, _Bool right, size_t sz, char *str, size_t len) {
  if (sz == (size_t) -1 || len >= sz) {
    gomp_display_string (buffer, size, ret, str, len);
  }
}
static void gomp_display_hostname (char *buffer, size_t size, size_t *ret, _Bool right, size_t sz) {
  {
    char buf[256];
    char *b = buf;
    size_t len = 256;
    do {
      b[len - 1] = '\0';
      if (gethostname (b, len - 1) == 0) {
	size_t l = strlen (b);
	if (l < len - 1) {
	  gomp_display_string_len (buffer, size, ret, right, sz, b, l);
	  if (b != buf) free (b);
	  return;
	}
      }
      if (len == 1048576) break;
      len = len * 2;
      if (len == 512) b = gomp_malloc (len);
      else b = gomp_realloc (b, len);
    }
    while (1);
  }
};
size_t gomp_display_affinity (char *buffer, size_t size, const char *format, gomp_thread_handle handle, struct gomp_team_state *ts, unsigned int place) {
  size_t ret = 0;
  do {
    const char *p = (__extension__ (__builtin_constant_p ( '%' ) && !__builtin_constant_p ( format ) && ( '%' ) == '\0' ? (char *) __rawmemchr ( format , '%' ) : __builtin_strchr ( format , '%' ))) ;
    _Bool zero = 0 ;
    _Bool right = 0 ;
    size_t sz = -1;
    char c;
    int val;
    if (p == ((void *)0) ) p = (__extension__ (__builtin_constant_p ( '\0' ) && !__builtin_constant_p ( format ) && ( '\0' ) == '\0' ? (char *) __rawmemchr ( format , '\0' ) : __builtin_strchr ( format , '\0' ))) ;
    c = *p;
    switch (c) {
    case 't': val = omp_get_team_num ();
      goto do_int;
    case 'T': val = omp_get_num_teams ();
    case 'L': val = ts->level;
    case 'N': val = ts->team ? ts->team->nthreads : 1;
    case 'a': val = ts->team ? ts->team->prev_ts.team_id : -1;
      goto do_int;
    case 'H': gomp_display_hostname (buffer, size, &ret, right, sz);
      goto do_int;
    case 'i': {
      char buf[3 * (sizeof (handle) + sizeof (uintptr_t) + sizeof (int)) + 4];
      if (sizeof (__builtin_choose_expr (__builtin_classify_type (handle) == 5, (uintptr_t) __builtin_choose_expr (__builtin_classify_type (handle) == 1 || __builtin_classify_type (handle) == 5, handle, 0), __builtin_choose_expr (__builtin_classify_type (handle) == 1 || __builtin_classify_type (handle) == 5, handle, 0))) == sizeof (unsigned long)) sprintf (buf, "0x%lx", (unsigned long) __builtin_choose_expr (__builtin_classify_type (handle) == 5, (uintptr_t) __builtin_choose_expr (__builtin_classify_type (handle) == 1 || __builtin_classify_type (handle) == 5, handle, 0), __builtin_choose_expr (__builtin_classify_type (handle) == 1 || __builtin_classify_type (handle) == 5, handle, 0)));
    }
      break;
    do_int: gomp_display_int (buffer, size, &ret, zero, right, sz, val);
      break;
    default: gomp_fatal ("unsupported type %c in affinity format", c);
    }
    format = p + 1;
  }
  while (1);
}
