#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Round up integer to the next multiple of `alignment`.
/// - Parameters:
///   - value: Value to align (bytes)
///   - alignment: Alignment boundary (power of two recommended)
/// - Returns: Aligned value
@inline(__always)
public func alignUp(_ value: Int, to alignment: Int) -> Int {
    let mask = alignment - 1
    return (value + mask) & ~mask
}

/// Round up to a page multiple using current OS page size.
@inline(__always)
public func ceilToPages(_ value: Int) -> Int {
    return alignUp(value, to: pageSize())
}

/// C-ABI: Test wrapper for `alignUp` used by C tests.
@_cdecl("ft_align_up_test")
public func ft_align_up_test(_ value: Int64, _ alignment: Int32) -> Int64 {
    return Int64(alignUp(Int(value), to: Int(alignment)))
}

/// C-ABI: Test wrapper for `ceilToPages` used by C tests.
@_cdecl("ft_ceil_pages_test")
public func ft_ceil_pages_test(_ value: Int64) -> Int64 {
    return Int64(ceilToPages(Int(value)))
}

/// C-ABI: Write a C string to file descriptor without heap allocations.
@_cdecl("ft_write_str_fd")
public func ft_write_str_fd(_ cstr: UnsafePointer<CChar>?, _ fd: Int32) {
    guard let cstr = cstr else { return }
    var len: Int = 0
    var p = cstr
    while p.pointee != 0 {
        len &+= 1
        p = p.advanced(by: 1)
    }
    _ = write(fd, cstr, len)
}


