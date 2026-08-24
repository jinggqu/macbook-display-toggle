CC := xcrun clang
SWIFTC := xcrun swiftc
ARCH ?= arm64
MACOSX_DEPLOYMENT_TARGET ?= 13.0
VERSION ?= 0.2.1
CFLAGS := -std=c11 -O2 -Wall -Wextra -Werror -arch $(ARCH) \
	-mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET)
SWIFTFLAGS := -O -warnings-as-errors -swift-version 5 \
	-target $(ARCH)-apple-macosx$(MACOSX_DEPLOYMENT_TARGET) \
	-module-cache-path build/module-cache
CORE_GRAPHICS := -framework CoreGraphics
APP_FRAMEWORKS := -framework AppKit -framework CoreGraphics

CLI := build/display-toggle
ALIASES := build/don build/doff
APP_NAME := MacBookDisplayToggle.app
APP := build/$(APP_NAME)
APP_EXECUTABLE := $(APP)/Contents/MacOS/MacBookDisplayToggle
APP_INFO := $(APP)/Contents/Info.plist
CORE_OBJECT := build/display-control.o
MENU_POLICY_TEST := build/menu-policy-tests
DMG_ROOT := build/dmg-root
DMG_APP_NAME := MacBook Display Toggle.app
RELEASE_DMG := build/MacBook-Display-Toggle-v$(VERSION)-macOS-$(ARCH).dmg
RELEASE_SHA := $(RELEASE_DMG).sha256
PREFIX ?= /usr/local
BINDIR := $(DESTDIR)$(PREFIX)/bin

.PHONY: all app clean cli install release test verify

all: cli app

cli: $(CLI) $(ALIASES)

app: $(APP_EXECUTABLE)

$(CLI): display-toggle.c display-control.c display-control.h
	@mkdir -p build
	$(CC) $(CFLAGS) display-toggle.c display-control.c -o $@ $(CORE_GRAPHICS)

$(ALIASES): $(CLI)
	ln -sf display-toggle $@

$(CORE_OBJECT): display-control.c display-control.h
	@mkdir -p build
	$(CC) $(CFLAGS) -c display-control.c -o $@

$(APP_EXECUTABLE): app/main.swift app/MenuPolicy.swift app/Info.plist \
		display-control.h $(CORE_OBJECT)
	@mkdir -p "$(APP)/Contents/MacOS"
	cp app/Info.plist "$(APP_INFO)"
	$(SWIFTC) $(SWIFTFLAGS) app/main.swift app/MenuPolicy.swift $(CORE_OBJECT) \
		-import-objc-header display-control.h $(APP_FRAMEWORKS) \
		-o "$(APP_EXECUTABLE)"
	codesign --force --deep --sign - "$(APP)"

$(MENU_POLICY_TEST): app/MenuPolicy.swift tests/MenuPolicyTests.swift
	@mkdir -p build
	$(SWIFTC) $(SWIFTFLAGS) -parse-as-library \
		app/MenuPolicy.swift tests/MenuPolicyTests.swift -o $@

test: $(MENU_POLICY_TEST)
	$(MENU_POLICY_TEST)

install: cli
	install -d $(BINDIR)
	install -m 755 $(CLI) $(BINDIR)/display-toggle
	ln -sf display-toggle $(BINDIR)/don
	ln -sf display-toggle $(BINDIR)/doff

verify: all test
	plutil -lint "$(APP_INFO)"
	codesign --verify --deep --strict --verbose=2 "$(APP)"
	@file $(CLI) "$(APP_EXECUTABLE)"

release: verify
	rm -rf "$(DMG_ROOT)"
	rm -f "$(RELEASE_DMG)" "$(RELEASE_SHA)"
	mkdir -p "$(DMG_ROOT)"
	ditto --norsrc --noextattr --noqtn --noacl \
		"$(APP)" "$(DMG_ROOT)/$(DMG_APP_NAME)"
	ln -s /Applications "$(DMG_ROOT)/Applications"
	codesign --verify --deep --strict --verbose=2 \
		"$(DMG_ROOT)/$(DMG_APP_NAME)"
	hdiutil create -quiet -volname "MacBook Display Toggle" \
		-srcfolder "$(DMG_ROOT)" -ov -format UDZO "$(RELEASE_DMG)"
	hdiutil verify "$(RELEASE_DMG)"
	cd build && shasum -a 256 "$(notdir $(RELEASE_DMG))" \
		> "$(notdir $(RELEASE_SHA))"

clean:
	rm -rf build
