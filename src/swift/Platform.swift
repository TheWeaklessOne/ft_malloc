#if os(Linux)
import Glibc
#else
import Darwin
#endif

@_cdecl("ft_page_size")
public func ft_page_size() -> Int32 {
#if os(Linux)
    let ps = sysconf(Int32(_SC_PAGESIZE))
    return ps > 0 ? Int32(ps) : Int32(getpagesize())
#else
    return Int32(getpagesize())
#endif
}

@inline(__always)
public func pageSize() -> Int {
    return Int(ft_page_size())
}


