#include <assert.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>

typedef void* (*malloc_fn)(size_t);
typedef void (*free_fn)(void*);

typedef struct {
    malloc_fn mymalloc;
    free_fn myfree;
    unsigned seed;
} worker_args;

static void *load_lib(const char *path) {
    void *h = dlopen(path, RTLD_NOW);
    if (!h) { fprintf(stderr, "dlopen: %s\n", dlerror()); return NULL; }
    return h;
}

static void *worker(void *argp) {
    worker_args *args = (worker_args*)argp;
    void *ptrs[128] = {0};
    for (int iter = 0; iter < 5000; ++iter) {
        int idx = rand_r(&args->seed) % 128;
        if (ptrs[idx]) {
            args->myfree(ptrs[idx]);
            ptrs[idx] = NULL;
        } else {
            size_t sz;
            switch (rand_r(&args->seed) % 3) {
                case 0: sz = (rand_r(&args->seed) % 512) + 1; break; // tiny
                case 1: sz = (rand_r(&args->seed) % 4096) + 513; break; // small
                default: sz = (rand_r(&args->seed) % (1<<20)) + 5000; break; // large-ish up to ~1MB
            }
            void *p = args->mymalloc(sz);
            assert(p);
            ptrs[idx] = p;
        }
    }
    for (int i = 0; i < 128; ++i) if (ptrs[i]) args->myfree(ptrs[i]);
    return NULL;
}

int main(void) {
    void *h = load_lib("./build/libft_malloc.so");
    assert(h);
    malloc_fn mymalloc = (malloc_fn)dlsym(h, "malloc");
    free_fn myfree = (free_fn)dlsym(h, "free");
    assert(mymalloc && myfree);

    const int threads = 8;
    pthread_t tids[threads];
    worker_args args[threads];
    for (int i = 0; i < threads; ++i) {
        args[i].mymalloc = mymalloc;
        args[i].myfree = myfree;
        args[i].seed = (unsigned)time(NULL) ^ (unsigned)(uintptr_t)&args[i] ^ (unsigned)i;
        int rc = pthread_create(&tids[i], NULL, worker, &args[i]);
        assert(rc == 0);
    }
    for (int i = 0; i < threads; ++i) pthread_join(tids[i], NULL);

    printf("S13 multithread stress passed.\n");
    return 0;
}


