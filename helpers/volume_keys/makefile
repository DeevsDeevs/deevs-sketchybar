bin/volume_keys: volume_keys.m
	mkdir -p bin
	clang -fobjc-arc -O2 -framework Foundation -framework ApplicationServices -framework CoreAudio -framework CoreFoundation -framework IOKit volume_keys.m -o bin/volume_keys

clean:
	rm -rf bin
