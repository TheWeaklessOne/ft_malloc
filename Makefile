# Cross-platform Makefile for FTMalloc (Swift-first allocator)

SHELL := /bin/bash

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
OBJ_DIR := $(BUILD_DIR)/obj
OBJECTS := $(patsubst src/c/%.c,$(OBJ_DIR)/%.o,$(C_SOURCES))

SWIFT_COMMON_FLAGS := -O -emit-library -parse-as-library -module-name FTMalloc

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
    SWIFT_PLATFORM_FLAGS := -Xlinker -lpthread
    NM := nm -D
else
    SWIFT_PLATFORM_FLAGS :=
    NM := nm -gU
endif

.PHONY: all clean fclean re test docs symbols tests-c linux-setup linux-test

all: $(LIB_PATH) symlink

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

$(LIB_PATH): $(BUILD_DIR) $(OBJ_DIR) $(SWIFT_SOURCES) $(OBJECTS)
	@if [ -z "$(SWIFT_SOURCES)" ]; then \
		echo "No Swift sources found in src/swift" >&2; \
		exit 1; \
	fi
	$(SWIFTC) $(SWIFT_COMMON_FLAGS) $(SWIFT_PLATFORM_FLAGS) $(SWIFT_SOURCES) $(OBJECTS) -o $(LIB_PATH)

symlink: $(LIB_PATH)
	@ln -sfn $(LIB_NAME) $(LIB_SYMLINK)

symbols: $(LIB_PATH)
	@echo "Exported symbols:" && $(NM) $(LIB_PATH) | egrep "[[:space:]](malloc|free|realloc|show_alloc_mem)$$" || true

tests-c: $(BUILD_DIR)/tests/test_util $(BUILD_DIR)/tests/test_metadata $(BUILD_DIR)/tests/test_zone $(BUILD_DIR)/tests/test_alloc $(BUILD_DIR)/tests/test_free $(BUILD_DIR)/tests/test_large $(BUILD_DIR)/tests/test_api_basic $(BUILD_DIR)/tests/test_realloc $(BUILD_DIR)/tests/test_show $(BUILD_DIR)/tests/test_mt
	@DYLD_LIBRARY_PATH=$(BUILD_DIR) LD_LIBRARY_PATH=$(BUILD_DIR) $(BUILD_DIR)/tests/test_util | cat
	@DYLD_LIBRARY_PATH=$(BUILD_DIR) LD_LIBRARY_PATH=$(BUILD_DIR) $(BUILD_DIR)/tests/test_metadata | cat
	@DYLD_LIBRARY_PATH=$(BUILD_DIR) LD_LIBRARY_PATH=$(BUILD_DIR) $(BUILD_DIR)/tests/test_zone | cat
	@DYLD_LIBRARY_PATH=$(BUILD_DIR) LD_LIBRARY_PATH=$(BUILD_DIR) $(BUILD_DIR)/tests/test_alloc | cat
	@DYLD_LIBRARY_PATH=$(BUILD_DIR) LD_LIBRARY_PATH=$(BUILD_DIR) $(BUILD_DIR)/tests/test_free | cat
	@DYLD_LIBRARY_PATH=$(BUILD_DIR) LD_LIBRARY_PATH=$(BUILD_DIR) $(BUILD_DIR)/tests/test_large | cat
	@DYLD_LIBRARY_PATH=$(BUILD_DIR) LD_LIBRARY_PATH=$(BUILD_DIR) $(BUILD_DIR)/tests/test_api_basic | cat
	@DYLD_LIBRARY_PATH=$(BUILD_DIR) LD_LIBRARY_PATH=$(BUILD_DIR) $(BUILD_DIR)/tests/test_realloc | cat
	@DYLD_LIBRARY_PATH=$(BUILD_DIR) LD_LIBRARY_PATH=$(BUILD_DIR) $(BUILD_DIR)/tests/test_show | cat
	@DYLD_LIBRARY_PATH=$(BUILD_DIR) LD_LIBRARY_PATH=$(BUILD_DIR) $(BUILD_DIR)/tests/test_mt | cat

$(BUILD_DIR)/tests:
	@mkdir -p $(BUILD_DIR)/tests

$(OBJ_DIR):
	@mkdir -p $(OBJ_DIR)

$(OBJ_DIR)/%.o: src/c/%.c | $(OBJ_DIR)
	$(CC) -fPIC -O2 -c $< -o $@

$(BUILD_DIR)/tests/test_util: all $(BUILD_DIR)/tests tests/c/test_util.c
	$(CC) -std=c11 -Wall -Wextra -O2 -o $(BUILD_DIR)/tests/test_util tests/c/test_util.c -ldl

$(BUILD_DIR)/tests/test_metadata: all $(BUILD_DIR)/tests tests/c/test_metadata.c
	$(CC) -std=c11 -Wall -Wextra -O2 -o $(BUILD_DIR)/tests/test_metadata tests/c/test_metadata.c -ldl

$(BUILD_DIR)/tests/test_zone: all $(BUILD_DIR)/tests tests/c/test_zone.c
	$(CC) -std=c11 -Wall -Wextra -O2 -o $(BUILD_DIR)/tests/test_zone tests/c/test_zone.c -ldl

$(BUILD_DIR)/tests/test_alloc: all $(BUILD_DIR)/tests tests/c/test_alloc.c
	$(CC) -std=c11 -Wall -Wextra -O2 -o $(BUILD_DIR)/tests/test_alloc tests/c/test_alloc.c -ldl

$(BUILD_DIR)/tests/test_free: all $(BUILD_DIR)/tests tests/c/test_free.c
	$(CC) -std=c11 -Wall -Wextra -O2 -o $(BUILD_DIR)/tests/test_free tests/c/test_free.c -ldl

$(BUILD_DIR)/tests/test_large: all $(BUILD_DIR)/tests tests/c/test_large.c
	$(CC) -std=c11 -Wall -Wextra -O2 -o $(BUILD_DIR)/tests/test_large tests/c/test_large.c -ldl

$(BUILD_DIR)/tests/test_api_basic: all $(BUILD_DIR)/tests tests/c/test_api_basic.c
	$(CC) -std=c11 -Wall -Wextra -O2 -o $(BUILD_DIR)/tests/test_api_basic tests/c/test_api_basic.c -ldl

$(BUILD_DIR)/tests/test_realloc: all $(BUILD_DIR)/tests tests/c/test_realloc.c
	$(CC) -std=c11 -Wall -Wextra -O2 -o $(BUILD_DIR)/tests/test_realloc tests/c/test_realloc.c -ldl

$(BUILD_DIR)/tests/test_show: all $(BUILD_DIR)/tests tests/c/test_show.c
	$(CC) -std=c11 -Wall -Wextra -O2 -o $(BUILD_DIR)/tests/test_show tests/c/test_show.c -ldl

$(BUILD_DIR)/tests/test_mt: all $(BUILD_DIR)/tests tests/c/test_mt.c
	$(CC) -std=c11 -Wall -Wextra -O2 -o $(BUILD_DIR)/tests/test_mt tests/c/test_mt.c -ldl -lpthread

test: all symbols tests-c

docs:
	@echo "[docs] DocC generation requires Swift toolchain with docc plugin (Xcode or swift-docc-plugin). Skipping if unavailable." && mkdir -p build/docs && cp -R Sources/FTMalloc.docc build/docs/ || true

linux-setup:
	@bash tools/linux-setup.sh

linux-test:
	@bash tools/linux-test.sh

clean:
	@rm -rf $(BUILD_DIR)

fclean: clean

re: fclean all


