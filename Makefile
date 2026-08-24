CC := xcrun clang
CFLAGS := -std=c11 -O2 -Wall -Wextra -Werror
FRAMEWORKS := -framework CoreGraphics
TARGET := build/display-toggle
ALIASES := build/don build/doff
PREFIX ?= /usr/local
BINDIR := $(DESTDIR)$(PREFIX)/bin

.PHONY: all clean install

all: $(TARGET) $(ALIASES)

$(TARGET): display-toggle.c
	@mkdir -p build
	$(CC) $(CFLAGS) $< -o $@ $(FRAMEWORKS)

$(ALIASES): $(TARGET)
	ln -sf display-toggle $@

install: all
	install -d $(BINDIR)
	install -m 755 $(TARGET) $(BINDIR)/display-toggle
	ln -sf display-toggle $(BINDIR)/don
	ln -sf display-toggle $(BINDIR)/doff

clean:
	rm -f $(TARGET) $(ALIASES)
