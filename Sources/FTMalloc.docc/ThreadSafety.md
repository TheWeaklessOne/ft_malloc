# Thread Safety

A single global `pthread_mutex` serializes allocator mutations. Public C-ABI functions lock around critical sections. Reentrancy during bootstrap is handled by initializing the mutex on first use from a tiny C shim.

Future work includes per-zone locks or lock-free freelists for reduced contention.
