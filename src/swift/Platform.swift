#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// C‑ABI: Return OS page size in bytes.
@_cdecl("ft_page_size")
public func ft_page_size() -> Int32 {
#if os(Linux)
    let ps = sysconf(Int32(_SC_PAGESIZE))
    return ps > 0 ? Int32(ps) : Int32(getpagesize())
#else
    return Int32(getpagesize())
#endif
}

/// Return page size in bytes.
///
/// Thin Swift convenience wrapper over ``ft_page_size()`` used throughout
/// the allocator to size mappings and compute alignment multiples.
@inline(__always)
public func pageSize() -> Int {
    return Int(ft_page_size())
}


