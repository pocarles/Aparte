.PHONY: build test check package run clean

build:
	swift build

test:
	swift test

check: test package
	dist/Aparte.app/Contents/MacOS/Aparte --runtime-acceptance
	git diff --check
	codesign --verify --deep --strict dist/Aparte.app

package:
	./scripts/package-app.sh

run: package
	open dist/Aparte.app

clean:
	swift package clean
	rm -rf dist
