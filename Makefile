.PHONY: generate build run clean test

generate:
	xcodegen generate

build: generate
	xcodebuild -project PersonalHistorian.xcodeproj \
		-scheme PersonalHistorian \
		-configuration Debug \
		SYMROOT=build \
		build

run: build
	open build/Debug/PersonalHistorian.app

clean:
	xcodebuild clean -project PersonalHistorian.xcodeproj -scheme PersonalHistorian
	rm -rf build

test: generate
	xcodebuild test -project PersonalHistorian.xcodeproj -scheme PersonalHistorian -destination 'platform=macOS'
