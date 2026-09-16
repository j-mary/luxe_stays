# LuxeStays - developer entry points.
.PHONY: help bootstrap patch-platforms mock run run-emulator run-ios run-lan \
        adb-reverse ip analyze format test coverage integration \
        integration-emulator integration-ios ci clean

FLUTTER ?= fvm flutter
DART ?= fvm dart
FLAVOR ?= dev
PORT   ?= 8080
DEVICE ?=

# Default device IDs for the platform-specific targets. Override either value
# at the command line when more than one matching device is available.
ANDROID_DEVICE ?= emulator-5554
IOS_DEVICE ?= $(shell xcrun simctl list devices booted 2>/dev/null | sed -nE 's/.*\(([0-9A-F-]{36})\).*/\1/p' | head -1)

# Where the app should look for the mock back end.
#
#   localhost   iOS simulator, macOS/desktop, Chrome, and any Android device
#               for which `make adb-reverse` has been run
#   10.0.2.2    Android emulator (its alias for the host machine's loopback)
#   <LAN IP>    physical Android device on the same Wi-Fi
#
# On Android, "localhost" is the HANDSET, not your Mac. That is the single most
# common reason the app cannot reach a mock server that is plainly running.
HOST ?= localhost
BASE  = http://$(HOST):$(PORT)
DEVICE_ARG = $(if $(strip $(DEVICE)),-d $(DEVICE))

DEFINES = \
	--dart-define=FLAVOR=$(FLAVOR) \
	--dart-define=API_BASE_URL=$(BASE) \
	--dart-define=SYNXIS_BASE_URL=$(BASE)/synxis \
	--dart-define=SYNXIS_BOOKING_ENGINE_URL=$(BASE)/be \
	--dart-define=SALESFORCE_BASE_URL=$(BASE)/salesforce \
	--dart-define=CMS_BASE_URL=$(BASE)/cms \
	--dart-define=LEONARDO_BASE_URL=$(BASE)/leonardo \
	--dart-define=LEONARDO_AI_BASE_URL=$(BASE)/leonardo-ai \
	--dart-define=PSP_HOSTED_PAGE_URL=$(BASE)/pay

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Fetch dependencies
	$(FLUTTER) pub get

patch-platforms: ## Re-apply the WebView platform settings (only after regenerating hosts)
	bash tool/patch_platforms.sh

mock: ## Run the mock SynXis / Salesforce / CMS / Leonardo / PSP back end
	$(DART) run tool/mock_server/server.dart --port $(PORT)

adb-reverse: ## Android on USB: tunnel the device's localhost:8080 to this Mac
	adb reverse tcp:$(PORT) tcp:$(PORT)
	@echo 'Device localhost now points at this machine; plain `make run` will work.'

ip: ## Print this Mac's LAN IP (for a physical device on Wi-Fi)
	@ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || \
		echo "could not determine a LAN IP - check System Settings > Network"

run: ## Run against mocks; set DEVICE=<id> to skip Flutter's device prompt
	@echo "→ app will call $(BASE)"
	$(FLUTTER) run $(DEVICE_ARG) $(DEFINES)

run-emulator: HOST = 10.0.2.2
run-emulator: DEVICE = $(ANDROID_DEVICE)
run-emulator: run ## Run on Android emulator-5554; override ANDROID_DEVICE=...

run-ios: HOST = localhost
run-ios: DEVICE = $(IOS_DEVICE)
run-ios: ## Run on the first booted iOS simulator
	@if [ -z "$(DEVICE)" ]; then echo 'No booted iOS simulator found.'; exit 1; fi
	@$(MAKE) run HOST="$(HOST)" DEVICE="$(DEVICE)" FLUTTER="$(FLUTTER)" DART="$(DART)"

run-lan: HOST = $(shell ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
run-lan: run ## Run on a physical device over Wi-Fi (uses this Mac's LAN IP)

analyze: ## Static analysis
	$(FLUTTER) analyze

format: ## Format all Dart sources
	$(DART) format lib test integration_test tool

test: ## Unit + widget tests
	$(FLUTTER) test

coverage: ## Unit + widget tests with coverage report
	$(FLUTTER) test --coverage
	@echo "lcov report at coverage/lcov.info"

integration: ## Integration tests (needs a booted device/emulator + mock server)
	$(FLUTTER) test integration_test $(DEVICE_ARG) $(DEFINES)

integration-emulator: HOST = 10.0.2.2
integration-emulator: DEVICE = $(ANDROID_DEVICE)
integration-emulator: integration ## Integration test on Android emulator-5554

integration-ios: HOST = localhost
integration-ios: DEVICE = $(IOS_DEVICE)
integration-ios: ## Integration test on the first booted iOS simulator
	@if [ -z "$(DEVICE)" ]; then echo 'No booted iOS simulator found.'; exit 1; fi
	@$(MAKE) integration HOST="$(HOST)" DEVICE="$(DEVICE)" FLUTTER="$(FLUTTER)" DART="$(DART)"

ci: bootstrap format analyze test ## What CI runs

clean:
	$(FLUTTER) clean
