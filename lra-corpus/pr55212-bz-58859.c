// -O2 -mno-lra

typedef signed char __int8_t;
typedef unsigned char __uint8_t;
typedef short int __int16_t;
typedef short unsigned int __uint16_t;
typedef long int __int32_t;
typedef long unsigned int __uint32_t;
typedef long long int __int64_t;
typedef long long unsigned int __uint64_t;
typedef signed char __int_least8_t;
typedef unsigned char __uint_least8_t;
typedef short int __int_least16_t;
typedef short unsigned int __uint_least16_t;
typedef long int __int_least32_t;
typedef long unsigned int __uint_least32_t;
typedef long long int __int_least64_t;
typedef long long unsigned int __uint_least64_t;
typedef long long int __intmax_t;
typedef long long unsigned int __uintmax_t;
typedef int __intptr_t;
typedef unsigned int __uintptr_t;
typedef int ptrdiff_t;
typedef unsigned int size_t;
typedef long int wchar_t;

typedef unsigned long long uint64;
typedef unsigned long uint32;
typedef unsigned short uint16;
typedef unsigned char uint8;
typedef long long int64;
typedef long int32;
typedef short int16;
typedef char int8;
typedef volatile uint64 vuint64;
typedef volatile uint32 vuint32;
typedef volatile uint16 vuint16;
typedef volatile uint8 vuint8;
typedef volatile int64 vint64;
typedef volatile int32 vint32;
typedef volatile int16 vint16;
typedef volatile int8 vint8;typedef uint32 ptr_t;

typedef __int8_t int8_t ;
typedef __uint8_t uint8_t ;
typedef __int16_t int16_t ;
typedef __uint16_t uint16_t ;
typedef __int32_t int32_t ;
typedef __uint32_t uint32_t ;
typedef __int64_t int64_t ;
typedef __uint64_t uint64_t ;
typedef __intmax_t intmax_t;
typedef __uintmax_t uintmax_t;
typedef __intptr_t intptr_t;
typedef __uintptr_t uintptr_t;



int irq_disable(void);
void irq_restore(int v);

static  __inline__ __attribute__((__always_inline__)) 
void dcache_pref_block(const void *src)
{
  __asm__ __volatile__("pref @%0\n" : : "r" (src) : "memory" );
}


typedef struct {
    int irq_state;
} g2_ctx_t;

static inline g2_ctx_t g2_lock(void) {
    g2_ctx_t ctx;

    ctx.irq_state = irq_disable();    (*((vuint32 *)0xa05f781C)) = 1;
    (*((vuint32 *)0xa05f783C)) = 1;
    (*((vuint32 *)0xa05f785C)) = 1;

    while((*(vuint32 const *)0xa05f688c) & ((1 << 5) | (1 << 4)));

    return ctx;
}

static inline void g2_unlock(g2_ctx_t ctx) {

    (*((vuint32 *)0xa05f781C)) = 0;
    (*((vuint32 *)0xa05f783C)) = 0;
    (*((vuint32 *)0xa05f785C)) = 0;

    irq_restore(ctx.irq_state);
}



void g2_fifo_wait(void);

void sq_lock(void *dest);
void sq_unlock(void);
void sq_wait(void);


void snd_pcm16_split_sq(uint32_t *data, uintptr_t left, uintptr_t right, size_t size) {
    g2_ctx_t ctx;
    uint32_t i;
    uint16 *s = (uint16 *)data;
    size_t remain = size;
    uint32_t *masked_left;
    uint32_t *masked_right;    left |= 0x00800000;
    right |= 0x00800000;

    masked_left = ((uint32_t *)(void *) (0xe0000000 | ((uintptr_t)(left) & 0x03ffffe0)));
    masked_right = ((uint32_t *)(void *) (0xe0000000 | ((uintptr_t)(right) & 0x03ffffe0)));

    sq_lock((void *)left);
    dcache_pref_block(s);    g2_fifo_wait();    for(; remain >= 128; remain -= 128) {        for(i = 0; i < 16; i += 2) {
            masked_left[i / 2] = (s[i * 2] << 16) | s[(i + 1) * 2];
        }        dcache_pref_block(masked_left);        for(i = 16; i < 32; i += 2) {
            masked_left[i / 2] = (s[i * 2] << 16) | s[(i + 1) * 2];
        }        dcache_pref_block(masked_left + 8);
        masked_left += 16;        for(i = 0; i < 16; i += 2) {
            masked_right[i / 2] = (s[(i * 2) + 1] << 16) | s[((i + 1) * 2) + 1];
        }        dcache_pref_block(masked_right);        for(i = 16; i < 32; i += 2) {
            masked_right[i / 2] = (s[(i * 2) + 1] << 16) | s[((i + 1) * 2) + 1];
        }        dcache_pref_block(masked_right + 8);
        masked_right += 16;
        s += 64;
    }

    sq_unlock();

    if(remain) {
        left |= 0xa0000000;
        right |= 0xa0000000;
        left += size - remain;
        right += size - remain;

        ctx = g2_lock();
        sq_wait();

        for(; remain >= 4; remain -= 4) {
            *((vuint16 *)left) = *s++;
            *((vuint16 *)right) = *s++;
            left += 2;
            right += 2;
        }
        g2_unlock(ctx);
    }

}
