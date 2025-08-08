#include <stddef.h>

// Swift-implemented functions (C symbols)
void *ft_malloc_impl(unsigned long size);
void ft_free_impl(void *ptr);
void *ft_realloc_impl(void *ptr, unsigned long size);
void ft_show_alloc_mem_impl(void);

void *malloc(size_t size) {
    return ft_malloc_impl((unsigned long)size);
}

void free(void *ptr) {
    ft_free_impl(ptr);
}

void *realloc(void *ptr, size_t size) {
    return ft_realloc_impl(ptr, (unsigned long)size);
}

void show_alloc_mem(void) {
    ft_show_alloc_mem_impl();
}

// Optional: demo mode query. The Swift side may export ft_is_demo_mode_enabled
// only when built with -D FTMALLOC_DEMO. Declare it weak; return 0 if absent.
#if defined(__APPLE__) || defined(__linux__)
extern int ft_is_demo_mode_enabled(void) __attribute__((weak));
#else
extern int ft_is_demo_mode_enabled(void);
#endif

int ft_demo_mode(void) {
    if (ft_is_demo_mode_enabled) {
        return ft_is_demo_mode_enabled();
    }
    return 0;
}


