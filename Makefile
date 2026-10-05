# Builds Chime: the Rust core (core/) as a static library, the Swift app
# (Sources/) on top of it, and the two bundled into build/Chime.app.

APP := build/Chime.app
# The release artifact: what CI uploads and the Homebrew cask downloads.
ZIP := build/Chime-aarch64-apple-darwin.zip
INSTALLED_APP := /Applications/Chime.app
CORE_LIB := core/target/release/libchime_core.a
SWIFT_BIN := .build/release/Chime

# Resources/Info.plist is the source of truth; scripts/release.sh bumps it.
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
BUNDLE_ID := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" Resources/Info.plist)
# CI passes its run number; local builds are "1".
BUILD_NUMBER ?= 1
# "-" signs ad hoc, which makes macOS forget the Accessibility grant on every
# rebuild. Name a certificate from `security find-identity -p codesigning` to
# keep it: make app SIGN_IDENTITY="My Certificate"
SIGN_IDENTITY ?= -

.PHONY: app zip core run install test icon screenshots version clean

app: core
	@# SwiftPM does not notice a changed static library, so force a relink.
	@if [ $(CORE_LIB) -nt $(SWIFT_BIN) ]; then rm -f $(SWIFT_BIN); fi
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(SWIFT_BIN) $(APP)/Contents/MacOS/Chime
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set CFBundleVersion $(BUILD_NUMBER)" $(APP)/Contents/Info.plist
	codesign --force --sign "$(SIGN_IDENTITY)" $(APP)
	@echo "Built $(APP) $(VERSION) (signed with: $(SIGN_IDENTITY))"

zip: app
	@rm -f $(ZIP)
	ditto -c -k --keepParent $(APP) $(ZIP)
	@shasum -a 256 $(ZIP)

core:
	cargo build --release --manifest-path core/Cargo.toml --target-dir core/target

# Quits a running copy first so the new build is the one that opens.
run: app
	@pkill -f "^$(abspath $(APP))/Contents/MacOS/Chime" && sleep 0.5 || true
	open $(APP)

install: app
	@# Another app could be called Chime; only ever replace this one.
	@if [ -e $(INSTALLED_APP) ] && [ "$$(defaults read $(INSTALLED_APP)/Contents/Info CFBundleIdentifier 2>/dev/null)" != "$(BUNDLE_ID)" ]; then \
		echo "$(INSTALLED_APP) is a different app; not replacing it."; exit 1; \
	fi
	@pkill -f "^$(INSTALLED_APP)/Contents/MacOS/Chime" && sleep 0.5 || true
	rm -rf $(INSTALLED_APP)
	cp -R $(APP) $(INSTALLED_APP)
	open $(INSTALLED_APP)

test:
	cargo test --manifest-path core/Cargo.toml --target-dir core/target

icon:
	swift scripts/make-icon.swift Resources/AppIcon.icns

# README images: the real UI rendered with sample apps (no personal data, no
# permissions needed), placed on a desktop-style backdrop.
screenshots: core
	swift build -c release
	@mkdir -p docs build/shots
	@for shot in menu-bar styles settings; do \
		$(SWIFT_BIN) --demo-snapshot $$shot build/shots/$$shot.png && \
		swift scripts/compose-screenshot.swift build/shots/$$shot.png docs/$$shot.png || exit 1; \
	done
	sips -s format png -z 256 256 Resources/AppIcon.icns --out docs/icon.png > /dev/null

version:
	@echo $(VERSION)

clean:
	rm -rf build .build core/target
