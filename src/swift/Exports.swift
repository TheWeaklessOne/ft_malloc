import Swift
#if os(Linux)
import Glibc
#else
import Darwin
#endif

@_cdecl("malloc")
public func ft_malloc(_ size: UInt) -> UnsafeMutableRawPointer? {
    // Temporary stub to verify symbol export and linking
    // Return NULL for now to avoid accidental allocations before allocator exists
    return nil
}

@_cdecl("free")
public func ft_free(_ ptr: UnsafeMutableRawPointer?) {
    // Temporary stub
}

@_cdecl("realloc")
public func ft_realloc(_ ptr: UnsafeMutableRawPointer?, _ size: UInt) -> UnsafeMutableRawPointer? {
    // Temporary stub
    return nil
}

@_cdecl("show_alloc_mem")
public func ft_show_alloc_mem() {
    // Temporary stub: no output
}


