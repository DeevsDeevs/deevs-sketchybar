APP = bin/location.app
BIN = $(APP)/Contents/MacOS/location

$(BIN): location.m Info.plist
	mkdir -p $(APP)/Contents/MacOS
	cp Info.plist $(APP)/Contents/Info.plist
	clang -fobjc-arc -O2 -framework Foundation -framework CoreLocation \
		location.m -o $(BIN)
# TCC keys the Location Services grant to the code signature, so an unsigned
# bundle is never offered the prompt. Ad-hoc is enough, but the identity changes
# on every rebuild, which revokes the grant — same trap as the Accessibility one.
	codesign --force --sign - --identifier com.deevs.sketchybar.location $(APP)

clean:
	rm -rf bin
