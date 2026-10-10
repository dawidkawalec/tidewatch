SHELL := /bin/bash
PROJECT := Tidewatch.xcodeproj
SCHEME := Tidewatch
DERIVED := $(CURDIR)/.local-build
APP_NAME := Tidewatch.app
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath "$(DERIVED)" -skipPackagePluginValidation -skipMacroValidation
# The second grep drops macOS's own "[Connection] ... linkd" noise the test host prints.
# The indented "(in target '" lines are the compile errors the test action lists under "Testing failed:".
XCPRETTY := grep -E "error:|warning: .*(Tidewatch|TidewatchHook|TidewatchCore)|BUILD (SUCCEEDED|FAILED)|TEST (SUCCEEDED|FAILED)|Testing failed|^[[:space:]]+[^[:space:]].*\(in target '|✘|Test run with" | grep -v '\[Connection\]'

.PHONY: gen build test test-core test-hook release sign install run clean dist dist-dry publish site deploy-site

gen:
	xcodegen generate

build: gen
	set -o pipefail; $(XCODEBUILD) -configuration Debug CODE_SIGN_IDENTITY="-" build 2>&1 | $(XCPRETTY)

test-core:
	set -o pipefail; swift test --package-path Packages/TidewatchCore 2>&1 | tail -n 3

test: gen test-core
	set -o pipefail; $(XCODEBUILD) -configuration Debug CODE_SIGN_IDENTITY="-" test 2>&1 | $(XCPRETTY)
	@if [ -x scripts/test-hook.sh ]; then scripts/test-hook.sh; fi
	python3 -m unittest discover -s scripts -p 'test_*.py' 2>&1 | tail -n 1

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

# Local builds only: "Captylo Dev" has no Team ID, so library validation would refuse Sparkle
# (scripts/sign-app.sh). The dev entitlements turn it off; public builds keep it (scripts/dist.sh).
DEV_ENTITLEMENTS := $(DERIVED)/TidewatchDev.entitlements

sign:
	@mkdir -p "$(DERIVED)"
	@cp "$(CURDIR)/Tidewatch/Tidewatch.entitlements" "$(DEV_ENTITLEMENTS)"
	@/usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$(DEV_ENTITLEMENTS)"
	@if security find-identity -p codesigning "$(SIGN_KEYCHAIN)" 2>/dev/null | grep -q '"$(SIGN_NAME)"'; then \
		security unlock-keychain -p "$$(cat "$(SIGN_PASSWORD_FILE)")" "$(SIGN_KEYCHAIN)"; \
		ORIGINAL="$$(security list-keychains -d user | tr -d '"' | xargs)"; \
		trap 'security list-keychains -d user -s $$ORIGINAL' EXIT; \
		security list-keychains -d user -s $$ORIGINAL "$(SIGN_KEYCHAIN)"; \
		SIGN_ENTITLEMENTS="$(DEV_ENTITLEMENTS)" scripts/sign-app.sh "$(APP_PATH)" "$(SIGN_NAME)" "$(SIGN_KEYCHAIN)" && echo "Signed with $(SIGN_NAME)"; \
	else \
		echo "No '$(SIGN_NAME)' identity; signing ad-hoc"; \
		SIGN_ENTITLEMENTS="$(DEV_ENTITLEMENTS)" scripts/sign-app.sh "$(APP_PATH)" -; \
	fi

install: release
	@pkill -x Tidewatch || true
	@rm -rf "/Applications/$(APP_NAME)"
	@ditto "$(HOME)/Downloads/$(APP_NAME)" "/Applications/$(APP_NAME)"
	@echo "Installed to /Applications/$(APP_NAME)"

# Public build (docs/release.md): Developer ID, notarized and stapled app + DMG in dist/<version>/.
# Uploads the build to Apple for notarization: owner's go-ahead first.
dist:
	@[ -n "$(VERSION)" ] || { echo "usage: make dist VERSION=x.y.z"; exit 2; }
	scripts/dist.sh $(VERSION)

dist-dry:
	@[ -n "$(VERSION)" ] || { echo "usage: make dist-dry VERSION=x.y.z"; exit 2; }
	DRY_RUN=1 scripts/dist.sh $(VERSION)

# Download page (site/): local preview, and the live deploy to kawalec.pl/tidewatch and craftweb.pl/tidewatch.
site:
	@[ -n "$(VERSION)" ] || { echo "usage: make site VERSION=x.y.z"; exit 2; }
	scripts/site.sh preview $(VERSION)

# Uploads the DMG and the page to the server (deploy/local.env): owner's go-ahead first.
deploy-site:
	@[ -n "$(VERSION)" ] || { echo "usage: make deploy-site VERSION=x.y.z"; exit 2; }
	scripts/site.sh deploy $(VERSION)

# Public download page + GitHub release of dist/<version>/Tidewatch-<version>.dmg on the private repo
# (owner's go-ahead first).
publish:
	@[ -n "$(VERSION)" ] || { echo "usage: make publish VERSION=x.y.z"; exit 2; }
	@[ -f "dist/$(VERSION)/Tidewatch-$(VERSION).dmg" ] || { echo "run make dist VERSION=$(VERSION) first"; exit 1; }
	scripts/site.sh deploy $(VERSION)
	gh release create "v$(VERSION)" "dist/$(VERSION)/Tidewatch-$(VERSION).dmg" --title "Tidewatch $(VERSION)" --notes-file "dist/$(VERSION)/notes.md"

run:
	@if [ -d "/Applications/$(APP_NAME)" ]; then open "/Applications/$(APP_NAME)"; \
	else open "$(DERIVED)/Build/Products/Debug/$(APP_NAME)"; fi

clean:
	rm -rf "$(DERIVED)" Packages/TidewatchCore/.build
