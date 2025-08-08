#include <pthread.h>

// Single global mutex with static initializer to avoid races/UB.
// No extra global state is used.
static pthread_mutex_t g_mutex = PTHREAD_MUTEX_INITIALIZER;

void ft_mutex_init_if_needed(void) {
    // No-op when using static initializer.
}

void ft_lock(void) {
    pthread_mutex_lock(&g_mutex);
}

void ft_unlock(void) {
    pthread_mutex_unlock(&g_mutex);
}


