import Swift
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// C-ABI: malloc replacement. Returns NULL on error or zero-size.
@_cdecl("ft_malloc_impl")
public func ft_malloc_impl(_ size: UInt) -> UnsafeMutableRawPointer? {
    ft_mutex_init_if_needed()
    ft_lock()
    defer { ft_unlock() }
    if size == 0 { return nil }
    let result = ft_internal_alloc(Int(size))
    return result
}

/// C-ABI: free replacement. No-op on NULL.
@_cdecl("ft_free_impl")
public func ft_free_impl(_ ptr: UnsafeMutableRawPointer?) {
    ft_mutex_init_if_needed()
    ft_lock()
    defer { ft_unlock() }
    ft_internal_free(ptr)
}

/// C-ABI: realloc replacement.
@_cdecl("ft_realloc_impl")
public func ft_realloc_impl(_ ptr: UnsafeMutableRawPointer?, _ size: UInt) -> UnsafeMutableRawPointer? {
    ft_mutex_init_if_needed()
    ft_lock()
    defer { ft_unlock() }
    // realloc policy: if ptr == NULL -> malloc(size); if size == 0 -> free(ptr), return NULL
    if ptr == nil { return ft_internal_alloc(Int(size)) }
    if size == 0 { ft_internal_free(ptr); return nil }
    return ft_internal_realloc(ptr, Int(size))
}

// show_alloc_mem is implemented in Introspection.swift


