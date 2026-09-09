# Perapera — the macOS app.
#
# SPM builds the binary; this assembles the .app around it. There is no
# .xcodeproj on purpose -- the project is a plain Swift package, and the bundle
# is four files of metadata rather than a reason to adopt a project format.

CONFIG    ?= release
APP       := Perapera.app
BUILD_DIR := $(shell swift build -c $(CONFIG) --show-bin-path 2>/dev/null)
CONTENTS  := $(APP)/Contents

.PHONY: all build app run test clean icon check-kit install

all: app

build:
	swift build -c $(CONFIG)

test:
	swift test

# Regenerates the icon from tools/make-icon.swift. Rarely needed -- the .icns is
# committed -- but keeps the icon reproducible rather than a binary nobody can edit.
icon:
	swift tools/make-icon.swift Resources
	iconutil -c icns Resources/Perapera.iconset -o Resources/Perapera.icns

# Assembles the bundle, then ad-hoc signs it. Signing matters even unsigned-for-
# distribution: macOS keys a stable app identity off the signature, and without
# one, permissions and window state reset on every rebuild.
KIT := fluent

# An app bundled without fluent cannot read a database or grade a lesson, and
# git archive ships the commit -- not the working tree -- so an uncommitted
# edit would be silently absent. Fail here rather than at the first click.
check-kit:
	@test -f $(KIT)/.claude/hooks/update-db.py || { \
	  echo "error: $(KIT)/ is missing or incomplete."; exit 1; }
	@test -z "$$(git status --porcelain -- $(KIT))" || { \
	  echo "error: $(KIT)/ has uncommitted changes; git archive would not ship them."; \
	  git status --short -- $(KIT); exit 1; }

app: build check-kit
	@rm -rf $(APP)
	@mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	@cp $(BUILD_DIR)/PeraperaApp $(CONTENTS)/MacOS/PeraperaApp
	@cp Resources/Info.plist $(CONTENTS)/Info.plist
	@cp Resources/Perapera.icns $(CONTENTS)/Resources/Perapera.icns
	@if [ -d "$(BUILD_DIR)/Perapera_PeraperaApp.bundle" ]; then \
		cp -R "$(BUILD_DIR)/Perapera_PeraperaApp.bundle" $(CONTENTS)/Resources/; \
	fi
	@mkdir -p $(CONTENTS)/Resources/fluent
	@git archive HEAD:$(KIT) | tar -x -C $(CONTENTS)/Resources/fluent
	@git rev-parse HEAD > $(CONTENTS)/Resources/bundle-version.txt
	@codesign --force --sign - --timestamp=none $(APP) 2>/dev/null \
		|| echo "warning: ad-hoc signing failed; the app still runs"
	@echo "Built $(APP) from $$(cut -c1-8 $(CONTENTS)/Resources/bundle-version.txt)"

run: app
	open $(APP)

install: app
	@rm -rf /Applications/$(APP)
	@cp -R $(APP) /Applications/
	@echo "Installed /Applications/$(APP)"

clean:
	rm -rf .build $(APP)
