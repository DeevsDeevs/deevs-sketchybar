APP := bin/audiotap.app
BIN := $(APP)/Contents/MacOS/audiotap

$(BIN): audiotap.swift Info.plist
	mkdir -p $(APP)/Contents/MacOS
	cp Info.plist $(APP)/Contents/Info.plist
	xcrun swiftc -O -o $(BIN) audiotap.swift
	codesign --force --sign - --identifier com.deevs.sketchybar.audiotap $(APP)

clean:
	rm -rf bin
