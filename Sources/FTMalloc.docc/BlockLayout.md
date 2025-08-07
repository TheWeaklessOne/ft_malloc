# Block Layout

Each allocation is preceded by a `BlockHeader` containing size, free/used flag, links to neighbors, and zone base pointer. The user pointer returned by `malloc` points to the payload immediately after the header and is 16-byte aligned.

Coalescing merges adjacent free blocks by absorbing headers and adjusting links.
