APP_NAME := Notchi
PROJECT_DIR := notchi/notchi
DERIVED_DATA := $(PROJECT_DIR)/build
BUILT_APP := $(DERIVED_DATA)/Build/Products/Release/$(APP_NAME).app
INSTALL_DIR := /Applications

.PHONY: build install clean

build:
	xcodebuild -project $(PROJECT_DIR)/notchi.xcodeproj \
		-scheme notchi \
		-configuration Release \
		-derivedDataPath $(DERIVED_DATA) \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO

install: build
	cp -R $(BUILT_APP) $(INSTALL_DIR)/

clean:
	rm -rf $(DERIVED_DATA)
