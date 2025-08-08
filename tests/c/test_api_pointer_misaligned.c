#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdint.h>

typedef void *(*malloc_fn)(unsigned long);
typedef void (*free_fn)(void *);

static void *load_lib(const char *path) {
  void *h = dlopen(path, RTLD_NOW);
  if (!h) { fprintf(stderr, "dlopen: %s\n", dlerror()); return NULL; }
  return h;
}

int main(void) {
  void *h = load_lib("./build/libft_malloc.so");
  assert(h);
  malloc_fn my_malloc = (malloc_fn)dlsym(h, "malloc");
  free_fn my_free = (free_fn)dlsym(h, "free");
  assert(my_malloc && my_free);

  // Allocate and intentionally misalign the pointer before freeing.
  unsigned char *p = (unsigned char *)my_malloc(128);
  assert(p);
  unsigned char *q = p + 10; // misaligned/shifted pointer
  // Freeing a foreign/misaligned pointer is undefined; allocator must not crash.
  // Expectation: either ignore, or safely no-op, but never segfault.
  my_free(q);

  // Still usable after erroneous free attempt
  my_free(p);
  printf("API misaligned free smoke test passed.\n");
  return 0;
}


