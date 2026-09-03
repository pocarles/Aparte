.PHONY: build test check check-app-store check-direct package package-app-store-local package-direct-dry-run package-mas run clean

build:
	swift build

test:
	swift test

check: test package
	dist/Aparte.app/Contents/MacOS/Aparte --runtime-acceptance
	git diff --check
	codesign --verify --deep --strict dist/Aparte.app

check-app-store: test package-app-store-local
	dist/app-store/Aparte.app/Contents/MacOS/Aparte --runtime-acceptance --exercise-default-store
	./scripts/validate-app-store.sh
	git diff --check

check-direct: package-direct-dry-run

package-direct-dry-run:
	APARTE_OUTPUT_DIR="$${TMPDIR:-/tmp}/aparte-package-dry" APARTE_OVERWRITE=1 \
		./scripts/package-direct.sh --mode dry-run

package:
	./scripts/package-app.sh

package-app-store-local:
	DISTRIBUTION=app-store-local UNIVERSAL=1 ./scripts/package-app.sh

package-mas:
	./scripts/package-mas.sh

run: package
	open dist/Aparte.app

clean:
	swift package clean
	rm -rf dist
