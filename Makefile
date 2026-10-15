APP := build/Build/Products/Debug/NotchMVP.app
ADAPTER_SRC := ThirdParty/mediaremote-adapter
ADAPTER_BUILD := build/adapter
BUNDLE_ID := com.talatozcoban.notchmvp

.PHONY: gen adapter build run stop restart test log measure clean

gen:
	xcodegen generate --quiet

# mediaremote-adapter (BSD-3) kaynaktan derlenir; uygulamaya bağlanmaz, /usr/bin/perl yükler.
adapter: $(ADAPTER_BUILD)/MediaRemoteAdapter.framework

$(ADAPTER_BUILD)/MediaRemoteAdapter.framework:
	cmake -S $(ADAPTER_SRC) -B $(ADAPTER_BUILD) -DCMAKE_BUILD_TYPE=Release > /dev/null
	cmake --build $(ADAPTER_BUILD) > /dev/null

build: gen adapter
	xcodebuild -project NotchMVP.xcodeproj -scheme NotchMVP -configuration Debug \
		-derivedDataPath build -quiet build

run: build
	open $(APP)

stop:
	-osascript -e 'tell application id "$(BUNDLE_ID)" to quit'

restart: stop build
	sleep 1
	open $(APP)

test:
	swift test --package-path Packages/NotchCore

log:
	log show --last 5m --predicate 'subsystem == "$(BUNDLE_ID)"' --style compact

# Kapalı notch boşta ölçümü: imleci notch'tan uzak ve hareketsiz bırakın.
measure:
	swift Scripts/idle-probe.swift --name NotchMVP --seconds 60

clean:
	rm -rf build NotchMVP.xcodeproj
