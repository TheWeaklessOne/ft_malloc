#if os(Linux)
import Glibc
#else
import Darwin
#endif

// Global allocator state (one global allowed by subject)
public struct AllocatorGlobals {
    public var tinyHead: UnsafeMutableRawPointer?
    public var smallHead: UnsafeMutableRawPointer?
    public var largeHead: UnsafeMutableRawPointer?
}

@usableFromInline
internal var gAllocator = AllocatorGlobals(tinyHead: nil, smallHead: nil, largeHead: nil)



