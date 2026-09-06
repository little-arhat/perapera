# Fluent macOS app.
#
# SPM builds the binary; this assembles the .app around it. There is no
# .xcodeproj on purpose -- the project is a plain Swift package, and the bundle
# is four files of metadata rather than a reason to adopt a project format.

CONFIG    ?= release
APP       := Fluent.app
BUILD_DIR := $(shell swift build -c $(CONFIG) --show-bin-path 2>/dev/null)
CONTENTS  := $(APP)/Contents

.PHONY: all build app run test clean icon

all: app

build:
	swift build -c $(CONFIG)

test:
	swift test

# Regenerates the icon from tools/make-icon.swift. Rarely needed -- the .icns is
# committed -- but keeps the icon reproducible rather than a binary nobody can edit.
icon:
	swift tools/make-icon.swift Resources
	iconutil -c icns Resources/Fluent.iconset -o Resources/Fluent.icns

# Assembles the bundle, then ad-hoc signs it. Signing matters even unsigned-for-
# distribution: macOS keys a stable app identity off the signature, and without
# one, permissions and window state reset on every rebuild.
app: build
	@rm -rf $(APP)
	@mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	@cp $(BUILD_DIR)/FluentApp $(CONTENTS)/MacOS/FluentApp
	@cp Resources/Info.plist $(CONTENTS)/Info.plist
	@cp Resources/Fluent.icns $(CONTENTS)/Resources/Fluent.icns
	@if [ -d "$(BUILD_DIR)/Fluent_FluentApp.bundle" ]; then \
		cp -R "$(BUILD_DIR)/Fluent_FluentApp.bundle" $(CONTENTS)/Resources/; \
	fi
	@codesign --force --sign - --timestamp=none $(APP) 2>/dev/null \
		|| echo "warning: ad-hoc signing failed; the app still runs"
	@echo "Built $(APP)"

run: app
	open $(APP)

clean:
	rm -rf .build $(APP)
