APP_NAME := PomodoroOverlay
BUNDLE_NAME := Pomodoro Overlay.app
CONFIG := release
BUILD_DIR := build
BUNDLE := $(BUILD_DIR)/$(BUNDLE_NAME)
INSTALL_DIR := $(HOME)/Applications
INSTALLED_BUNDLE := $(INSTALL_DIR)/$(BUNDLE_NAME)
EXECUTABLE := .build/$(CONFIG)/$(APP_NAME)

.PHONY: build bundle install run clean

build:
	swift build -c $(CONFIG)

bundle: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$(EXECUTABLE)" "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	chmod +x "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@echo "Built $(BUNDLE)"

install: bundle
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALLED_BUNDLE)"
	cp -R "$(BUNDLE)" "$(INSTALLED_BUNDLE)"
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(INSTALLED_BUNDLE)"
	@echo "Installed $(INSTALLED_BUNDLE)"

run: install
	open "$(INSTALLED_BUNDLE)"

clean:
	rm -rf .build $(BUILD_DIR)
