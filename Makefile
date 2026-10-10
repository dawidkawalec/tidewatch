SHELL := /bin/bash
PROJECT := Tidewatch.xcodeproj
SCHEME := Tidewatch
DERIVED := $(CURDIR)/.local-build
APP_NAME := Tidewatch.app
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath "$(DERIVED)" -skipPackagePluginValidation -skipMacroValidation
# The second grep drops macOS's own "[Connection] ... linkd" noise the test host prints.
# The indented "(in target '" lines are the compile errors the test action lists under "Testing failed:".
XCPRETTY := grep -E "error:|warning: .*(Tidewatch|TidewatchHook|TidewatchCore)|BUILD (SUCCEEDED|FAILED)|TEST (SUCCEEDED|FAILED)|Testing failed|^[[:space:]]+[^[:space:]].*\(in target '|✘|Test run with" | grep -v '\[Connection\]'

.PHONY: gen build test test-core test-hook release sign install run clean

gen:
	xcodegen generate

build: gen
	set -o pipefail; $(XCODEBUILD) -configuration Debug CODE_SIGN_IDENTITY="-" build 2>&1 | $(XCPRETTY)

test-core:
	set -o pipefail; swift test --package-path Packages/TidewatchCore 2>&1 | tail -n 3

test: gen test-core
	set -o pipefail; $(XCODEBUILD) -configuration Debug CODE_SIGN_IDENTITY="-" test 2>&1 | $(XCPRETTY)
	@if [ -x scripts/test-hook.sh ]; then scripts/test-hook.sh; fi

# Stable local signing identity shared with Captylo (scripts/setup-signing.sh in Captylo).
# Without it builds are signed ad-hoc. The signing keychain joins the search list only for the
# codesign call and the previous list comes back right after (also on failure).
SIGN_NAME := Captylo Dev
SIGN_KEYCHAIN := $(HOME)/Library/Keychains/captylo-dev.keychain-db
SIGN_PASSWORD_FILE := $(HOME)/.claude/secrets/captylo-dev-keychain.key

release: gen
	set -o pipefail; $(XCODEBUILD) -configuration Release CODE_SIGN_IDENTITY="-" build 2>&1 | $(XCPRETTY)
	@rm -rf "$(HOME)/Downloads/$(APP_NAME)"
	@ditto "$(DERIVED)/Build/Products/Release/$(APP_NAME)" "$(HOME)/Downloads/$(APP_NAME)"
	@xattr -cr "$(HOME)/Downloads/$(APP_NAME)"
	@$(MAKE) --no-print-directory sign APP_PATH="$(HOME)/Downloads/$(APP_NAME)"
	@echo "Release build copied to ~/Downloads/$(APP_NAME)"

sign:
	@if security find-identity -p codesigning "$(SIGN_KEYCHAIN)" 2>/dev/null | grep -q '"$(SIGN_NAME)"'; then \
		security unlock-keychain -p "$$(cat "$(SIGN_PASSWORD_FILE)")" "$(SIGN_KEYCHAIN)"; \
		ORIGINAL="$$(security list-keychains -d user | tr -d '"' | xargs)"; \
		trap 'security list-keychains -d user -s $$ORIGINAL' EXIT; \
		security list-keychains -d user -s $$ORIGINAL "$(SIGN_KEYCHAIN)"; \
		scripts/sign-app.sh "$(APP_PATH)" "$(SIGN_NAME)" "$(SIGN_KEYCHAIN)" && echo "Signed with $(SIGN_NAME)"; \
	else \
		echo "No '$(SIGN_NAME)' identity; signing ad-hoc"; \
		scripts/sign-app.sh "$(APP_PATH)" -; \
	fi

install: release
	@pkill -x Tidewatch || true
	@rm -rf "/Applications/$(APP_NAME)"
	@ditto "$(HOME)/Downloads/$(APP_NAME)" "/Applications/$(APP_NAME)"
	@echo "Installed to /Applications/$(APP_NAME)"

run:
	@if [ -d "/Applications/$(APP_NAME)" ]; then open "/Applications/$(APP_NAME)"; \
	else open "$(DERIVED)/Build/Products/Debug/$(APP_NAME)"; fi

clean:
	rm -rf "$(DERIVED)" Packages/TidewatchCore/.build
