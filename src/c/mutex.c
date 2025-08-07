#include <pthread.h>

static pthread_mutex_t g_mutex;
static int g_inited = 0;

void ft_mutex_init_if_needed(void) {
    if (!g_inited) {
        pthread_mutexattr_t attr;
        pthread_mutexattr_init(&attr);
        pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_NORMAL);
        pthread_mutex_init(&g_mutex, &attr);
        pthread_mutexattr_destroy(&attr);
        g_inited = 1;
    }
}

void ft_lock(void) {
    ft_mutex_init_if_needed();
    pthread_mutex_lock(&g_mutex);
}

void ft_unlock(void) {
    pthread_mutex_unlock(&g_mutex);
}


