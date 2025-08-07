import Swift
#if os(Linux)
import Glibc
#else
import Darwin
#endif

@_cdecl("ft_malloc_impl")
public func ft_malloc_impl(_ size: UInt) -> UnsafeMutableRawPointer? {
    // Temporary stub to verify symbol export and linking
    // Return NULL for now to avoid accidental allocations before allocator exists
    return nil
}

@_cdecl("ft_free_impl")
public func ft_free_impl(_ ptr: UnsafeMutableRawPointer?) {
    // Temporary stub
}

@_cdecl("ft_realloc_impl")
public func ft_realloc_impl(_ ptr: UnsafeMutableRawPointer?, _ size: UInt) -> UnsafeMutableRawPointer? {
    // Temporary stub
    return nil
}

@_cdecl("ft_show_alloc_mem_impl")
public func ft_show_alloc_mem_impl() {
    // Temporary stub: no output
}


