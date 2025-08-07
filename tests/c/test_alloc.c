#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdint.h>

typedef void* (*alloc_fn)(int32_t);
typedef int (*int_fn)(void);

static void *load_lib(const char *path) {
    void *h = dlopen(path, RTLD_NOW);
    if (!h) { fprintf(stderr, "dlopen: %s\n", dlerror()); return NULL; }
    return h;
}

int main(void) {
    void *h = load_lib("./build/libft_malloc.so");
    assert(h);
    alloc_fn alloc = (alloc_fn)dlsym(h, "ft_debug_alloc");
    int_fn page = (int_fn)dlsym(h, "ft_page_size");
    assert(alloc && page);

    void *p1 = alloc(1);
    void *p2 = alloc(32);
    void *p3 = alloc(512);

    assert(p1 && p2 && p3);
    // Alignment check: addresses should be multiple of 16
    assert(((uintptr_t)p1 % 16) == 0);
    assert(((uintptr_t)p2 % 16) == 0);
    assert(((uintptr_t)p3 % 16) == 0);

    printf("S05 alloc tests passed.\n");
    return 0;
}


