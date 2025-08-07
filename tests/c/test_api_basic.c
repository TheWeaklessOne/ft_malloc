#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdint.h>

typedef void* (*malloc_fn)(size_t);
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
    free_fn myfree = (free_fn)dlsym(h, "free");
    assert(mymalloc && myfree);

    // malloc(0) policy: expect NULL
    void *z = mymalloc(0);
    assert(z == NULL);

    // free(NULL) is no-op
    myfree(NULL);

    // small alloc/free
    void *p = mymalloc(64);
    assert(p && ((uintptr_t)p % 16) == 0);
    myfree(p);

    printf("S08 API basic tests passed.\n");
    return 0;
}


