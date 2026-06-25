APP_NAME := PomodoroOverlay
BUNDLE_NAME := Pomodoro Overlay.app
CONFIG := release
BUILD_DIR := build
BUNDLE := $(BUILD_DIR)/$(BUNDLE_NAME)
EXECUTABLE := .build/$(CONFIG)/$(APP_NAME)

.PHONY: build bundle run clean

build:
	swift build -c $(CONFIG)

bundle: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$(EXECUTABLE)" "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	chmod +x "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@echo "Built $(BUNDLE)"

run: bundle
	open "$(BUNDLE)"

clean:
	rm -rf .build $(BUILD_DIR)
