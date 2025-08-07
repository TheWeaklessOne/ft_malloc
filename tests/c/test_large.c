#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdint.h>

typedef void* (*alloc_fn)(int32_t);
typedef void (*free_fn)(void*);

static void *load_lib(const char *path) {
    void *h = dlopen(path, RTLD_NOW);
    if (!h) { fprintf(stderr, "dlopen: %s\n", dlerror()); return NULL; }
    return h;
}

int main(void) {
    void *h = load_lib("./build/libft_malloc.so");
    assert(h);
    alloc_fn alloc = (alloc_fn)dlsym(h, "ft_debug_alloc");
    free_fn ffree = (free_fn)dlsym(h, "ft_free_impl");
    assert(alloc && ffree);

    // Request > small threshold to force LARGE path
    void *p = alloc(5000000);
    assert(p);
    assert(((uintptr_t)p % 16) == 0);
    ffree(p);

    printf("S07 large tests passed.\n");
    return 0;
}


