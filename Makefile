SWIFT_ENV = HOME=$(CURDIR)/.build/home
XCODE_DEVELOPER_DIR ?= /Applications/Xcode-beta.app/Contents/Developer
XCODEBUILD_ENV = DEVELOPER_DIR=$(XCODE_DEVELOPER_DIR)
XCODE_DERIVED_DATA ?= $(CURDIR)/.build/XcodeDerivedData
XCODE_SIM_DESTINATION ?= generic/platform=iOS Simulator
XCODE_DEVICE_DESTINATION ?= generic/platform=iOS
XCODE_PROJECT = Pult.xcodeproj/project.pbxproj
PULT_APP_GROUP = 010000000000000000000604
PULT_CORE_GROUP = 010000000000000000000605
PULT_APP_SOURCES = 010000000000000000000521
PULT_CORE_SOURCES = 010000000000000000000522
PULT_WIDGETS_GROUP = 010000000000000000000606
PULT_WIDGETS_SOURCES = 010000000000000000000523

.PHONY: build core-check metadata-check test test-ship-testflight ship-testflight verify verify-full xcode-build-device xcode-build-simulator xcode-env-check xcode-project-check

build:
	$(SWIFT_ENV) swift build --disable-sandbox

core-check:
	$(SWIFT_ENV) swift run --disable-sandbox PultCoreCheck

metadata-check:
	xmllint --noout Pult.xcodeproj/xcshareddata/xcschemes/*.xcscheme
	plutil -lint $(XCODE_PROJECT) Sources/PultApp/Supporting/Info.plist Pult.xcodeproj/xcuserdata/nyetwork.xcuserdatad/xcschemes/xcschememanagement.plist Sources/PultWidgets/Supporting/Info.plist Sources/PultApp/Pult.entitlements Sources/PultWidgets/PultWidgets.entitlements

xcode-project-check:
	@missing=0; \
	check_section() { \
		id="$$1"; \
		name="$$2"; \
		section="$$3"; \
		file="$$4"; \
		if ! awk -v id="$$id" -v name="$$name" '\
			index($$0, id " /*") { in_section = 1 } \
			in_section && index($$0, "/* " name " */") { found = 1 } \
			in_section && $$0 ~ /^[[:space:]]*};/ { in_section = 0 } \
			END { exit found ? 0 : 1 } \
		' "$(XCODE_PROJECT)"; then \
			echo "Missing Xcode $$section entry: $$file"; \
			missing=1; \
		fi; \
	}; \
	check_sources_phase() { \
		id="$$1"; \
		name="$$2"; \
		section="$$3"; \
		file="$$4"; \
		if ! awk -v id="$$id" -v name="$$name" '\
			index($$0, id " /* Sources */ = {") { in_phase = 1 } \
			in_phase && index($$0, "/* " name " in Sources */") { found = 1 } \
			in_phase && $$0 ~ /^[[:space:]]*};/ { in_phase = 0 } \
			END { exit found ? 0 : 1 } \
		' "$(XCODE_PROJECT)"; then \
			echo "Missing Xcode $$section sources build phase entry: $$file"; \
			missing=1; \
		fi; \
	}; \
	for file in Sources/PultApp/*.swift; do \
		name=$$(basename "$$file"); \
		if ! grep -Fq "path = $$name;" "$(XCODE_PROJECT)"; then \
			echo "Missing Xcode file reference: $$file"; \
			missing=1; \
		fi; \
		check_section "$(PULT_APP_GROUP)" "$$name" "PultApp group" "$$file"; \
		check_sources_phase "$(PULT_APP_SOURCES)" "$$name" "Pult app target" "$$file"; \
	done; \
	for file in Sources/PultCore/*.swift; do \
		name=$$(basename "$$file"); \
		if ! grep -Fq "path = $$name;" "$(XCODE_PROJECT)"; then \
			echo "Missing Xcode file reference: $$file"; \
			missing=1; \
		fi; \
		check_section "$(PULT_CORE_GROUP)" "$$name" "PultCore group" "$$file"; \
		check_sources_phase "$(PULT_CORE_SOURCES)" "$$name" "PultCore target" "$$file"; \
	done; \
	for file in Sources/PultWidgets/*.swift; do \
		name=$$(basename "$$file"); \
		if ! grep -Fq "path = $$name;" "$(XCODE_PROJECT)"; then \
			echo "Missing Xcode file reference: $$file"; \
			missing=1; \
		fi; \
		check_section "$(PULT_WIDGETS_GROUP)" "$$name" "PultWidgets group" "$$file"; \
		check_sources_phase "$(PULT_WIDGETS_SOURCES)" "$$name" "PultWidgets target" "$$file"; \
	done; \
	exit $$missing

test:
	$(SWIFT_ENV) swift test --disable-sandbox

test-ship-testflight:
	bash Scripts/test-ship-testflight.sh

xcode-env-check:
	@test -x "$(XCODE_DEVELOPER_DIR)/usr/bin/xcodebuild" || (echo "Set XCODE_DEVELOPER_DIR to a full Xcode developer directory."; exit 1)
	$(XCODEBUILD_ENV) xcodebuild -version
	@$(XCODEBUILD_ENV) xcodebuild -showsdks | grep -q "iphoneos" || (echo "Full Xcode with iOS SDKs is required; Command Line Tools are not enough."; exit 1)

xcode-build-simulator: xcode-env-check metadata-check xcode-project-check
	$(XCODEBUILD_ENV) xcodebuild -project Pult.xcodeproj -scheme Pult -destination "$(XCODE_SIM_DESTINATION)" -derivedDataPath "$(XCODE_DERIVED_DATA)" CODE_SIGNING_ALLOWED=NO build

xcode-build-device: xcode-env-check metadata-check xcode-project-check
	$(XCODEBUILD_ENV) xcodebuild -project Pult.xcodeproj -scheme "Pult Release Direct" -configuration Release -destination "$(XCODE_DEVICE_DESTINATION)" -derivedDataPath "$(XCODE_DERIVED_DATA)" build

verify:
	$(SWIFT_ENV) swift run --disable-sandbox PultCoreCheck
	$(SWIFT_ENV) swift build --disable-sandbox
	xmllint --noout Pult.xcodeproj/xcshareddata/xcschemes/*.xcscheme
	plutil -lint $(XCODE_PROJECT) Sources/PultApp/Supporting/Info.plist Pult.xcodeproj/xcuserdata/nyetwork.xcuserdatad/xcschemes/xcschememanagement.plist Sources/PultWidgets/Supporting/Info.plist Sources/PultApp/Pult.entitlements Sources/PultWidgets/PultWidgets.entitlements
	$(MAKE) xcode-project-check

verify-full: verify xcode-build-simulator

ship-testflight:
	MESSAGE="$(MESSAGE)" DRY_RUN="$(DRY_RUN)" ALLOW_MAIN="$(ALLOW_MAIN)" XCODE_DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" bash Scripts/ship-testflight.sh
