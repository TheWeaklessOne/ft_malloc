#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Global lists of allocation metadata managed by the allocator.
///
/// The allocator maintains three disjoint intrusive lists:
/// - ``AllocatorGlobals/tinyHead``: Head of the zone list that stores TINY-class allocations.
/// - ``AllocatorGlobals/smallHead``: Head of the zone list that stores SMALL-class allocations.
/// - ``AllocatorGlobals/largeHead``: Head of the list that stores LARGE allocations, each backed by
///   a dedicated mapping where the ``BlockHeader/isLarge`` flag is set.
public struct AllocatorGlobals {
    /// Head pointer for the first TINY zone mapping.
    /// The value is either `nil` (no TINY zones yet) or an address that points to a `ZoneHeader`.
    public var tinyHead: UnsafeMutableRawPointer?
    /// Head pointer for the first SMALL zone mapping.
    /// The value is either `nil` (no SMALL zones yet) or an address that points to a `ZoneHeader`.
    public var smallHead: UnsafeMutableRawPointer?
    /// Head pointer for the intrusive list of LARGE blocks.
    /// Each node in this list is a `BlockHeader` whose payload occupies the remainder of the mapping.
    public var largeHead: UnsafeMutableRawPointer?
}

/// Process‑wide mutable allocator state.
///
/// This singleton is intentionally unexported as a symbol to avoid accidental external linkage.
/// All reads and writes must be protected by the global mutex (see ``ft_lock()``/``ft_unlock()``).
@usableFromInline
internal var gAllocator = AllocatorGlobals(tinyHead: nil, smallHead: nil, largeHead: nil)

