#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>

typedef int (*zone_roundtrip_fn)(int);
typedef int (*int_fn)(void);

static void *load_lib(const char *path) {
    void *h = dlopen(path, RTLD_NOW);
    if (!h) { fprintf(stderr, "dlopen: %s\n", dlerror()); return NULL; }
    return h;
}

int main(void) {
    void *h = load_lib("./build/libft_malloc.so");
    assert(h);
    zone_roundtrip_fn zrt = (zone_roundtrip_fn)dlsym(h, "ft_debug_zone_roundtrip");
    int_fn page = (int_fn)dlsym(h, "ft_page_size");
    assert(zrt && page);
    int ps = page();
    int sizes[3];
    for (int k = 1; k <= 3; ++k) {
        sizes[k-1] = zrt(k);
        assert(sizes[k-1] > 0);
        assert(sizes[k-1] % ps == 0);
    }
    printf("S04 zone tests passed.\n");
    return 0;
}


