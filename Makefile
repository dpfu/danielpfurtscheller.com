.PHONY: all build server clean test

all: build

build:
	rm -rf public
	hugo --gc --minify --cleanDestinationDir

server:
	hugo server --bind 127.0.0.1 --port 1313 --disableFastRender

clean:
	rm -rf public

test:
	rm -rf public
	hugo --gc --minify --cleanDestinationDir --printPathWarnings --printUnusedTemplates --panicOnWarning
	git diff --check
