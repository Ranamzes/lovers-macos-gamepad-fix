APP_NAME = Lovers Fix.app
BIN_NAME = Lovers Fix
RELEASE_ZIP = releases/Lovers-Fix-macOS.zip

CC = clang
CFLAGS = -O2 -framework Cocoa -arch arm64 -arch x86_64 -Wall

all: app zip

app:
	@echo "==> Building Universal Binary..."
	@mkdir -p "$(APP_NAME)/Contents/MacOS"
	@mkdir -p "$(APP_NAME)/Contents/Resources"
	$(CC) $(CFLAGS) src/main.m -o "$(APP_NAME)/Contents/MacOS/$(BIN_NAME)"
	@echo "==> Installing Info.plist and Icon..."
	@cp src/Info.plist "$(APP_NAME)/Contents/Info.plist"
	@cp src/AppIcon.icns "$(APP_NAME)/Contents/Resources/AppIcon.icns"
	@echo "==> Signing application bundle..."
	codesign --force --deep -s - "$(APP_NAME)"
	@codesign --verify --deep --strict "$(APP_NAME)"
	@echo "==> App bundle built successfully: $(APP_NAME)"

zip: app
	@echo "==> Packaging release zip..."
	@mkdir -p releases
	@rm -f "$(RELEASE_ZIP)"
	zip -r -q -y "$(RELEASE_ZIP)" "$(APP_NAME)"
	@echo "==> Release ready: $(RELEASE_ZIP)"

clean:
	rm -rf "$(APP_NAME)" releases

.PHONY: all app zip clean
