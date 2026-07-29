bin/volume_keys: volume_keys.c
	mkdir -p bin
	clang -std=c99 -O2 -framework ApplicationServices -framework CoreAudio -framework CoreFoundation -framework IOKit volume_keys.c -o bin/volume_keys

clean:
	rm -rf bin
