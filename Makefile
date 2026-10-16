APP := build/Build/Products/Debug/Browline.app
ADAPTER_SRC := ThirdParty/mediaremote-adapter
ADAPTER_BUILD := build/adapter
SESSIONS_BUILD := build/sessions
BUNDLE_ID := com.talatozcoban.browline
# Kendi imzanızla derlemek için: make run XCODE_FLAGS='DEVELOPMENT_TEAM=ABCDE12345'
# İmzasız yerel deneme: make run XCODE_FLAGS='CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM='
XCODE_FLAGS ?=

.PHONY: gen adapter sessions build run stop restart test log measure clean

gen:
	xcodegen generate --quiet

# mediaremote-adapter (BSD-3) kaynaktan derlenir; uygulamaya bağlanmaz, /usr/bin/perl yükler.
adapter: $(ADAPTER_BUILD)/MediaRemoteAdapter.framework

$(ADAPTER_BUILD)/MediaRemoteAdapter.framework:
	cmake -S $(ADAPTER_SRC) -B $(ADAPTER_BUILD) -DCMAKE_BUILD_TYPE=Release > /dev/null
	cmake --build $(ADAPTER_BUILD) > /dev/null

# Çoklu medya oturumu yardımcısı (kendi kodumuz); adaptör gibi /usr/bin/perl yükler.
sessions: $(SESSIONS_BUILD)/MediaSessions.dylib

$(SESSIONS_BUILD)/MediaSessions.dylib: Helpers/MediaSessions/MediaSessions.m
	mkdir -p $(SESSIONS_BUILD)
	clang -dynamiclib -fobjc-arc -fvisibility=default -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
		-Wall -framework Foundation -framework AppKit -o $@ $<

build: gen adapter sessions
	xcodebuild -project Browline.xcodeproj -scheme Browline -configuration Debug -skipPackagePluginValidation \
		-derivedDataPath build -quiet $(XCODE_FLAGS) build

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
	swift Scripts/idle-probe.swift --name Browline --seconds 60

clean:
	rm -rf build Browline.xcodeproj
