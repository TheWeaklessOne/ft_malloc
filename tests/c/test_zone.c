#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>

typedef int (*zone_roundtrip_fn)(int);
typedef int (*int_fn)(void);
typedef int (*block_header_size_fn)(void);
typedef void (*thresholds_fn)(int *, int *);

static void *load_lib(const char *path) {
  void *h = dlopen(path, RTLD_NOW);
  if (!h) {
    fprintf(stderr, "dlopen: %s\n", dlerror());
    return NULL;
  }
  return h;
}

int main(void) {
  void *h = load_lib("./build/libft_malloc.so");
  assert(h);
  zone_roundtrip_fn zrt = (zone_roundtrip_fn)dlsym(h, "ft_debug_zone_roundtrip");
  int_fn page = (int_fn)dlsym(h, "ft_page_size");
  block_header_size_fn bh_size = (block_header_size_fn)dlsym(h, "ft_block_header_size");
  thresholds_fn thr = (thresholds_fn)dlsym(h, "ft_tiny_small_thresholds");
  int_fn align_const = (int_fn)dlsym(h, "ft_alignment_const");
  assert(zrt && page && bh_size && thr && align_const);

  int ps = page();
  int bh = bh_size();
  int tinyMax = 0, smallMax = 0;
  thr(&tinyMax, &smallMax);
  int alignment = align_const();

  int sizes[3];
  // Only TINY(1) and SMALL(2) are zones; LARGE(3) uses dedicated mappings and
  // isn't created via createZone/zoneSizeFor.
  for (int k = 1; k <= 2; ++k) {
    sizes[k - 1] = zrt(k);
    assert(sizes[k - 1] > 0);
    assert(sizes[k - 1] % ps == 0);
  }

  long tinyPayload = (tinyMax + (alignment - 1)) & ~(long)(alignment - 1);
  long smallPayload = (smallMax + (alignment - 1)) & ~(long)(alignment - 1);
  long tinyPerBlock = bh + tinyPayload;
  long smallPerBlock = bh + smallPayload;

  // Ensure capacity for >= minBlocksPerZone blocks of the class (conservative, ignores ZoneHeader area)
  int (*min_blocks_fn)(void) = (int_fn)dlsym(h, "ft_min_blocks_per_zone");
  int min_blocks = 100;
  if (min_blocks_fn) min_blocks = min_blocks_fn();
  assert((long)sizes[0] >= (long)min_blocks * tinyPerBlock);   // TINY
  assert((long)sizes[1] >= (long)min_blocks * smallPerBlock);  // SMALL

  printf("S04 zone tests passed.\n");
  return 0;
}


