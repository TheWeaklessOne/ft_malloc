#include <unistd.h>
#include <stdint.h>

static void write_str(const char *s) {
    const char *p = s;
    while (*p) p++;
    (void)write(STDOUT_FILENO, s, (size_t)(p - s));
}

static void write_char(char c) { (void)write(STDOUT_FILENO, &c, 1); }

static void write_hex_u64(uint64_t v) {
    char buf[2 + 16];
    const char *hex = "0123456789ABCDEF";
    buf[0] = '0'; buf[1] = 'x';
    for (int i = 0; i < 16; ++i) {
        int shift = (15 - i) * 4;
        buf[2 + i] = hex[(v >> shift) & 0xF];
    }
    (void)write(STDOUT_FILENO, buf, sizeof(buf));
}

static void write_dec_u64(uint64_t v) {
    char buf[32];
    int i = 0;
    if (v == 0) { write_char('0'); return; }
    while (v > 0) { buf[i++] = (char)('0' + (v % 10)); v /= 10; }
    while (i--) write_char(buf[i]);
}

void ft_print_zone_header(const char *label, const void *addr) {
    write_str(label);
    write_str(" : ");
    write_hex_u64((uintptr_t)addr);
    write_char('\n');
}

void ft_print_block_range(const void *start, const void *end, unsigned long size) {
    write_hex_u64((uintptr_t)start);
    write_str(" - ");
    write_hex_u64((uintptr_t)end);
    write_str(" : ");
    write_dec_u64(size);
    write_str(" bytes\n");
}

void ft_print_total(unsigned long total) {
    write_str("Total : ");
    write_dec_u64(total);
    write_str(" bytes\n");
}


