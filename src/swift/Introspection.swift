#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// C bridge: print a zone header label and start address.
@_silgen_name("ft_print_zone_header")
func ft_print_zone_header(_ label: UnsafePointer<CChar>, _ addr: UnsafeRawPointer)

/// C bridge: print a single block range and the size (bytes).
@_silgen_name("ft_print_block_range")
func ft_print_block_range(_ start: UnsafeRawPointer, _ end: UnsafeRawPointer, _ size: UInt)

/// C bridge: print the total sum of allocated bytes.
@_silgen_name("ft_print_total")
func ft_print_total(_ total: UInt)

@inline(__always)
private func cstr(_ s: String) -> [CChar] {
    let arr = Array(s.utf8CString)
    return arr
}

/// C-ABI: show_alloc_mem implementation printing blocks by ascending address grouped by zone class.
@_cdecl("ft_show_alloc_mem_impl")
public func ft_show_alloc_mem_impl() {
    ft_mutex_init_if_needed()
    ft_lock()
    defer { ft_unlock() }
    var total: UInt = 0
    // TINY, SMALL, LARGE in that order
    func dumpList(_ label: String, _ head: UnsafeMutableRawPointer?) {
        let labelC = cstr(label)
        var z = head
        if let base = z { labelC.withUnsafeBufferPointer { buf in ft_print_zone_header(buf.baseAddress!, UnsafeRawPointer(base)) } }
        while let base = z {
            let zh = base.assumingMemoryBound(to: ZoneHeader.self)
            var cur = zh.pointee.firstBlock
            while let b = cur {
                let bh = b.assumingMemoryBound(to: BlockHeader.self)
                if !bh.pointee.isFree {
                    let start = UnsafeRawPointer(bh).advanced(by: blockHeaderSize())
                    let end = UnsafeRawPointer(bh).advanced(by: blockHeaderSize() + bh.pointee.size)
                    ft_print_block_range(start, end, UInt(bh.pointee.size))
                    total &+= UInt(bh.pointee.size)
                }
                cur = bh.pointee.next
            }
            z = zh.pointee.nextZone
        }
    }
    dumpList("TINY", gAllocator.tinyHead)
    dumpList("SMALL", gAllocator.smallHead)
    // LARGE blocks are maintained as list in gAllocator.largeHead via BlockHeader chain
    if let lh = gAllocator.largeHead {
        let labelC = cstr("LARGE")
        labelC.withUnsafeBufferPointer { buf in ft_print_zone_header(buf.baseAddress!, UnsafeRawPointer(lh)) }
        var cur: UnsafeMutableRawPointer? = lh
        while let b = cur {
            let bh = b.assumingMemoryBound(to: BlockHeader.self)
            let start = UnsafeRawPointer(bh).advanced(by: blockHeaderSize())
            let end = UnsafeRawPointer(bh).advanced(by: blockHeaderSize() + bh.pointee.size)
            ft_print_block_range(start, end, UInt(bh.pointee.size))
            total &+= UInt(bh.pointee.size)
            cur = bh.pointee.next
        }
    }
    ft_print_total(total)
}


