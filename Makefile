APP_NAME := MacReader
BUILD_DIR := build
DESTINATION := platform=macOS
INSTALL_DIR := /Applications

.PHONY: project build run install test clean

project:
	xcodegen generate

build: project
	xcodebuild -scheme $(APP_NAME) -configuration Release -destination '$(DESTINATION)' \
		-derivedDataPath $(BUILD_DIR) build

# Build and launch the app.
run: build
	open $(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app

# Build and copy the app into /Applications.
install: build
	rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	cp -R $(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app $(INSTALL_DIR)/

test:
	swift test --package-path MacReaderKit

clean:
	rm -rf $(BUILD_DIR)
