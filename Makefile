.PHONY: generate build run clean

generate:
	xcodegen generate

build: generate
	xcodebuild -project PersonalHistorian.xcodeproj \
		-scheme PersonalHistorian \
		-configuration Debug \
		build

run: build
	open build/Debug/PersonalHistorian.app

clean:
	xcodebuild clean -project PersonalHistorian.xcodeproj -scheme PersonalHistorian
	rm -rf build
