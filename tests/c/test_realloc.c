#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

typedef void* (*malloc_fn)(size_t);
typedef void* (*realloc_fn)(void*, size_t);
typedef void (*free_fn)(void*);

static void *load_lib(const char *path) {
    void *h = dlopen(path, RTLD_NOW);
    if (!h) { fprintf(stderr, "dlopen: %s\n", dlerror()); return NULL; }
    return h;
}

int main(void) {
    void *h = load_lib("./build/libft_malloc.so");
    assert(h);
    malloc_fn mymalloc = (malloc_fn)dlsym(h, "malloc");
    realloc_fn myrealloc = (realloc_fn)dlsym(h, "realloc");
    free_fn myfree = (free_fn)dlsym(h, "free");
    assert(mymalloc && myrealloc && myfree);

    // realloc(NULL, n) -> malloc(n)
    void *p = myrealloc(NULL, 100);
    assert(p);
    memset(p, 0xAB, 100);

    // grow
    void *q = myrealloc(p, 3000);
    assert(q);
    // shrink
    void *r = myrealloc(q, 32);
    assert(r);

    // realloc(ptr, 0) -> free(ptr), return NULL
    void *s = myrealloc(r, 0);
    assert(s == NULL);

    printf("S09 realloc tests passed.\n");
    return 0;
}


