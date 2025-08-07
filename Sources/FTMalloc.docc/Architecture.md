# Architecture

This allocator uses three allocation classes:

- TINY: up to 512 bytes
- SMALL: up to 4096 bytes
- LARGE: greater than 4096 bytes

TINY/SMALL blocks are served from pre-mapped zones created with `mmap`, each zone storing a `ZoneHeader` and a doubly-linked list of `BlockHeader`s. LARGE blocks are individually mapped.

On `free`, adjacent free blocks are coalesced. Empty zones are unmapped. A global `pthread_mutex` guards the allocator state; contention can be reduced later via fine-grained locks.
