SWIFT_ENV = HOME=$(CURDIR)/.build/home
XCODE_PROJECT = Pult.xcodeproj/project.pbxproj
PULT_APP_GROUP = 010000000000000000000604
PULT_CORE_GROUP = 010000000000000000000605
PULT_APP_SOURCES = 010000000000000000000521
PULT_CORE_SOURCES = 010000000000000000000522
PULT_WIDGETS_GROUP = 010000000000000000000606
PULT_WIDGETS_SOURCES = 010000000000000000000523

.PHONY: build core-check metadata-check test verify xcode-project-check

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

verify: build core-check metadata-check xcode-project-check
