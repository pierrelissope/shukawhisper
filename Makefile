APP_NAME   := ShukaWhisper
BUILD_DIR  := .build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR ?= /Applications

# With only the Command Line Tools installed (no Xcode), the swift-testing framework
# lives outside the default search paths, so point the compiler and linker at it.
DEV_FRAMEWORKS := $(shell xcode-select -p)/Library/Developer/Frameworks
ifneq ($(wildcard $(DEV_FRAMEWORKS)/Testing.framework),)
TEST_FLAGS := -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays -Xswiftc -F -Xswiftc $(DEV_FRAMEWORKS) -Xlinker -F -Xlinker $(DEV_FRAMEWORKS) -Xlinker -rpath -Xlinker $(DEV_FRAMEWORKS)
endif

.PHONY: build app run install test clean cert icon

## build: compile a release binary
build:
	swift build -c release --product $(APP_NAME)

## app: build and assemble a signed .app bundle in .build/
app:
	./scripts/build-app.sh

## run: build the app bundle and launch it
run: app
	-pkill -x $(APP_NAME) 2>/dev/null; sleep 0.3
	open $(APP_BUNDLE)

## install: build and copy the app to /Applications, then launch it
install: app
	-pkill -x $(APP_NAME) 2>/dev/null; sleep 0.3
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R $(APP_BUNDLE) "$(INSTALL_DIR)/"
	open "$(INSTALL_DIR)/$(APP_NAME).app"

## test: run the unit tests
test:
	swift test $(TEST_FLAGS)

## cert: create the local code-signing certificate (keeps macOS permissions across rebuilds)
cert:
	./scripts/make-cert.sh

## icon: regenerate AppIcon.icns from Resources/AppIcon.png
icon:
	./scripts/make-icon.sh

clean:
	rm -rf $(BUILD_DIR)
