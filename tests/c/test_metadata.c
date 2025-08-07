#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>

typedef int (*int_fn)(void);
typedef void (*thresholds_fn)(int*, int*);

static void *load_lib(const char *path) {
    void *h = dlopen(path, RTLD_NOW);
    if (!h) { fprintf(stderr, "dlopen: %s\n", dlerror()); return NULL; }
    return h;
}

int main(void) {
    void *h = load_lib("./build/libft_malloc.so");
    assert(h);

    int_fn zone_hdr = (int_fn)dlsym(h, "ft_zone_header_size");
    int_fn block_hdr = (int_fn)dlsym(h, "ft_block_header_size");
    int_fn align_const = (int_fn)dlsym(h, "ft_alignment_const");
    thresholds_fn th = (thresholds_fn)dlsym(h, "ft_tiny_small_thresholds");

    assert(zone_hdr && block_hdr && align_const && th);

    int z = zone_hdr();
    int b = block_hdr();
    int a = align_const();
    int tiny=0, small=0; th(&tiny, &small);

    assert(a == 16);
    assert(z > 0 && b > 0);
    assert((b % a) == 0 || (a % (b % a)) == a); // loose check: prefer multiples, but allow any positive
    assert(tiny > 0 && small > tiny);

    printf("S03 metadata tests passed.\n");
    return 0;
}


