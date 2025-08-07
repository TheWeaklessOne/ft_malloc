# Design

FTMalloc uses page-backed zones for TINY and SMALL allocations and dedicated mappings for LARGE. Each zone stores a linked list of blocks with headers; free blocks are coalesced on `free`. Thread safety is provided by a global pthread mutex. The allocator avoids using Swift heap constructs on critical paths.
