#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>

typedef void* (*malloc_fn)(size_t);
typedef void (*free_fn)(void*);
typedef void (*show_fn)(void);

static void *load_lib(const char *path) {
    void *h = dlopen(path, RTLD_NOW);
    if (!h) { fprintf(stderr, "dlopen: %s\n", dlerror()); return NULL; }
    return h;
}

int main(void) {
    void *h = load_lib("./build/libft_malloc.so");
    assert(h);
    malloc_fn mymalloc = (malloc_fn)dlsym(h, "malloc");
    free_fn myfree = (free_fn)dlsym(h, "free");
    show_fn show = (show_fn)dlsym(h, "show_alloc_mem");
    assert(mymalloc && myfree && show);
    void *p = mymalloc(100);
    void *q = mymalloc(5000);
    assert(p && q);
    show();
    myfree(p);
    myfree(q);
    printf("S10 show_alloc_mem tests passed.\n");
    return 0;
}


