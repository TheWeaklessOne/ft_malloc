#define _DARWIN_C_SOURCE
#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int (*page_size_fn)(void);
typedef long long (*align_up_fn)(long long, int);
typedef long long (*ceil_pages_fn)(long long);

static void *load_lib(const char *path) {
    void *h = dlopen(path, RTLD_NOW);
    if (!h) {
        fprintf(stderr, "dlopen failed: %s\n", dlerror());
        exit(2);
    }
    return h;
}

int main(void) {
    const char *libpath = "./build/libft_malloc.so";
    void *h = load_lib(libpath);
    page_size_fn ft_page_size = (page_size_fn)dlsym(h, "ft_page_size");
    align_up_fn ft_align_up_test = (align_up_fn)dlsym(h, "ft_align_up_test");
    ceil_pages_fn ft_ceil_pages_test = (ceil_pages_fn)dlsym(h, "ft_ceil_pages_test");

    if (!ft_page_size || !ft_align_up_test || !ft_ceil_pages_test) {
        fprintf(stderr, "dlsym failed: %s\n", dlerror());
        return 3;
    }

    int ps = ft_page_size();
    assert(ps > 0 && (ps & (ps - 1)) == 0); // power of two typical, but at least positive

    assert(ft_align_up_test(0, 16) == 0);
    assert(ft_align_up_test(1, 16) == 16);
    assert(ft_align_up_test(16, 16) == 16);
    assert(ft_align_up_test(17, 16) == 32);

    long long v = ps + 1;
    long long rounded = ft_ceil_pages_test(v);
    assert(rounded % ps == 0);
    assert(rounded >= v);

    printf("S02 util tests passed.\n");
    return 0;
}


