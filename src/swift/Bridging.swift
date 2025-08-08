@_silgen_name("ft_mutex_init_if_needed")
func ft_mutex_init_if_needed() -> Void

@_silgen_name("ft_lock")
func ft_lock() -> Void

@_silgen_name("ft_unlock")
func ft_unlock() -> Void

// C printing bridges
@_silgen_name("ft_print_zone_header")
func ft_print_zone_header(_ label: UnsafePointer<CChar>, _ addr: UnsafeRawPointer)

@_silgen_name("ft_print_block_range")
func ft_print_block_range(_ start: UnsafeRawPointer, _ end: UnsafeRawPointer, _ size: UInt)

@_silgen_name("ft_print_total")
func ft_print_total(_ total: UInt)

