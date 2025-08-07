import Swift
#if os(Linux)
import Glibc
#else
import Darwin
#endif

@_cdecl("ft_malloc_impl")
public func ft_malloc_impl(_ size: UInt) -> UnsafeMutableRawPointer? {
    ft_mutex_init_if_needed()
    ft_lock()
    defer { ft_unlock() }
    let result = ft_internal_alloc(Int(size))
    return result
}

@_cdecl("ft_free_impl")
public func ft_free_impl(_ ptr: UnsafeMutableRawPointer?) {
    ft_mutex_init_if_needed()
    ft_lock()
    defer { ft_unlock() }
    ft_internal_free(ptr)
}

@_cdecl("ft_realloc_impl")
public func ft_realloc_impl(_ ptr: UnsafeMutableRawPointer?, _ size: UInt) -> UnsafeMutableRawPointer? {
    // Implemented in S09.
    return nil
}

@_cdecl("ft_show_alloc_mem_impl")
public func ft_show_alloc_mem_impl() {
    // Temporary stub: no output
}


