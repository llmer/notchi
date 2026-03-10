APP_NAME := Notchi
PROJECT_DIR := notchi
DERIVED_DATA := $(PROJECT_DIR)/build
BUILT_APP := $(DERIVED_DATA)/Build/Products/Release/$(APP_NAME).app
INSTALL_DIR := /Applications

.PHONY: help build install clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

build: ## Build the Release app
	xcodebuild -project $(PROJECT_DIR)/notchi.xcodeproj \
		-scheme notchi \
		-configuration Release \
		-derivedDataPath $(DERIVED_DATA) \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO

install: build ## Build and install to /Applications
	cp -R $(BUILT_APP) $(INSTALL_DIR)/

clean: ## Remove build artifacts
	rm -rf $(DERIVED_DATA)
