# Cross-platform Makefile for FTMalloc (Swift-first allocator)

SHELL := /bin/zsh

# Resolve HOSTTYPE if empty
ifeq ($(HOSTTYPE),)
HOSTTYPE := $(shell uname -m)_$(shell uname -s)
endif

BUILD_DIR := build
LIB_NAME := libft_malloc_$(HOSTTYPE).so
LIB_PATH := $(BUILD_DIR)/$(LIB_NAME)
LIB_SYMLINK := $(BUILD_DIR)/libft_malloc.so

SWIFTC := swiftc
SWIFT_SOURCES := $(shell find src/swift -name '*.swift' 2>/dev/null)
C_SOURCES := $(shell find src/c -name '*.c' 2>/dev/null)

SWIFT_COMMON_FLAGS := -O -emit-library -parse-as-library -module-name FTMalloc

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
    SWIFT_PLATFORM_FLAGS :=
    NM := nm -D
else
    SWIFT_PLATFORM_FLAGS :=
    NM := nm -gU
endif

.PHONY: all clean fclean re test docs symbols

all: $(LIB_PATH) symlink

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

$(LIB_PATH): $(BUILD_DIR) $(SWIFT_SOURCES) $(C_SOURCES)
	@if [ -z "$(SWIFT_SOURCES)" ]; then \
		echo "No Swift sources found in src/swift" >&2; \
		exit 1; \
	fi
	$(SWIFTC) $(SWIFT_COMMON_FLAGS) $(SWIFT_PLATFORM_FLAGS) $(SWIFT_SOURCES) $(C_SOURCES) -o $(LIB_PATH)

symlink: $(LIB_PATH)
	@ln -sfn $(LIB_NAME) $(LIB_SYMLINK)

symbols: $(LIB_PATH)
	@echo "Exported symbols:" && $(NM) $(LIB_PATH) | egrep "[[:space:]](malloc|free|realloc|show_alloc_mem)$$" || true

test: all symbols
	@echo "[test] Placeholder: tests will be added in subsequent steps"

docs:
	@echo "[docs] Placeholder: DocC build will be added later"

clean:
	@rm -rf $(BUILD_DIR)

fclean: clean

re: fclean all


