APP_NAME := Pomodoro Overlay
SCHEME := PomodoroOverlay
CONFIG := Release
BUILD_DIR := build
DERIVED := $(BUILD_DIR)/DerivedData
BUNDLE := $(DERIVED)/Build/Products/$(CONFIG)/$(APP_NAME).app
INSTALL_DIR := $(HOME)/Applications
INSTALLED_BUNDLE := $(INSTALL_DIR)/$(APP_NAME).app
VERSION = $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$(BUNDLE)/Contents/Info.plist")
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# -destination pins the build to this Mac so xcodebuild never boots an iOS simulator.
# Local builds sign manually with the keychain's Apple Development certificate;
# Xcode Cloud uses the project's automatic signing instead.
XCODEBUILD := xcodebuild -project PomodoroOverlay.xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) \
	-destination 'platform=macOS' -derivedDataPath $(DERIVED) \
	CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Development" PROVISIONING_PROFILE_SPECIFIER=

.PHONY: project build install run dmg clean

project:
	xcodegen generate

build:
	$(XCODEBUILD) build -quiet

install: build
	mkdir -p "$(INSTALL_DIR)"
	-pkill -f "$(APP_NAME).app/Contents/MacOS/"
	rm -rf "$(INSTALLED_BUNDLE)"
	cp -R "$(BUNDLE)" "$(INSTALLED_BUNDLE)"
	$(LSREGISTER) -f "$(INSTALLED_BUNDLE)"
	@echo "Installed $(INSTALLED_BUNDLE)"

run: install
	open "$(INSTALLED_BUNDLE)"

dmg: build
	scripts/make-dmg.sh "$(BUNDLE)" "$(BUILD_DIR)/PomodoroOverlay-$(VERSION).dmg"

clean:
	rm -rf $(BUILD_DIR)
