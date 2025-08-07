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
    int (*count_tiny)(int) = (int (*)(int))dlsym(h, "ft_debug_count_zones");
    assert(alloc && ffree && count_tiny);

    int before = count_tiny(1);
    void *p1 = alloc(64);
    void *p2 = alloc(128);
    assert(p1 && p2);
    int mid = count_tiny(1);
    assert(mid >= before);
    ffree(p1);
    ffree(p2);
    int after = count_tiny(1);
    assert(after == before || after == before - 1 || after == before); // may reclaim zone; tolerate both

    printf("S06 free tests passed.\n");
    return 0;
}


