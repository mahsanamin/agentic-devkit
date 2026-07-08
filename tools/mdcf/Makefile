BINARY := mdcf
PKG    := ./cmd/mdcf
OUT    := bin
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS := -s -w -X main.Version=$(VERSION)

.PHONY: build build-mac-arm build-mac-intel build-linux release-mac install clean tidy vet

build:
	go build -ldflags '$(LDFLAGS)' -o $(OUT)/$(BINARY) $(PKG)

build-mac-arm:
	GOOS=darwin GOARCH=arm64 go build -ldflags '$(LDFLAGS)' -o $(OUT)/$(BINARY)-darwin-arm64 $(PKG)

build-mac-intel:
	GOOS=darwin GOARCH=amd64 go build -ldflags '$(LDFLAGS)' -o $(OUT)/$(BINARY)-darwin-amd64 $(PKG)

build-linux:
	GOOS=linux GOARCH=amd64 go build -ldflags '$(LDFLAGS)' -o $(OUT)/$(BINARY)-linux-amd64 $(PKG)

release-mac: build-mac-arm build-mac-intel
	lipo -create -output $(OUT)/$(BINARY)-darwin-universal $(OUT)/$(BINARY)-darwin-arm64 $(OUT)/$(BINARY)-darwin-amd64
	@echo "Universal binary: $(OUT)/$(BINARY)-darwin-universal"

install: build
	install -m 0755 $(OUT)/$(BINARY) /usr/local/bin/$(BINARY)
	@echo "Installed /usr/local/bin/$(BINARY)"

tidy:
	go mod tidy

vet:
	go vet ./...

clean:
	rm -rf $(OUT)
