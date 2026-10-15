// Notch'un çoklu medya oturumu yardımcısı: sistemdeki TÜM oynatıcıları (Chrome, Spotify, Music…)
// ayrı ayrı okur ve komutu doğrudan istenen oynatıcıya gönderir. mediaremote-adapter yalnız sistemin
// seçtiği tek oynatıcıyı verdiği için iki medya açıkken biri görünmüyordu.
//
// Uygulamaya bağlanmaz; /usr/bin/perl yükler (mediaremote-adapter ile aynı yol: macOS 15.4'ten beri
// mediaremoted yalnız com.apple. kimlikli süreçlere yanıt veriyor).
// ⚠️ Belgelenmemiş MediaRemote işlevleri. İmzalar macOS 27'de disassembly ve denemeyle doğrulandı
// (2026-10-16); işlev bulunamazsa süreç 2 ile çıkar, uygulama tek oturuma geri düşer.

#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

typedef void (*GetClientsFn)(dispatch_queue_t, void (^)(NSArray *));
typedef id (*GetLocalOriginFn)(void);
typedef CFTypeRef (*CreatePathFn)(id origin, id client, id player);
typedef void (*InfoForPlayerFn)(id path, Boolean includeArtwork, dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*StateForPlayerFn)(id path, dispatch_queue_t, void (^)(unsigned int));
typedef void (*SupportedCommandsFn)(id path, dispatch_queue_t, void (^)(NSArray *));
typedef Boolean (*SendToPlayerFn)(unsigned int command, NSDictionary *options, id path, unsigned int appOptions,
                                  dispatch_queue_t, void (^)(id result));
typedef int (*ClientPIDFn)(id client);
typedef NSString *(*ClientStringFn)(id client);
typedef void (*RegisterFn)(dispatch_queue_t);

static struct {
    void *handle;
    GetClientsFn getClients;
    GetLocalOriginFn localOrigin;
    CreatePathFn createPath;
    InfoForPlayerFn infoForPlayer;
    StateForPlayerFn stateForPlayer;
    SupportedCommandsFn supportedCommands;
    SendToPlayerFn sendToPlayer;
    ClientPIDFn clientPID;
    ClientStringFn clientBundleIdentifier;
    ClientStringFn clientParentBundleIdentifier;
    ClientStringFn clientDisplayName;
    RegisterFn registerForNotifications;
} mr;

static dispatch_queue_t callbackQueue;
static const int64_t callTimeout = 2 * NSEC_PER_SEC;
/// MRPlaybackState: 1 çalıyor, 2 duraklatıldı, 3 durdu.
static const unsigned int playbackStatePlaying = 1;
/// MRMediaRemoteCommandSeekToPlaybackPosition
static const unsigned int seekCommand = 24;

static NSString *constantNamed(const char *name) {
    NSString *__unsafe_unretained *pointer = (NSString *__unsafe_unretained *)dlsym(mr.handle, name);
    return pointer ? *pointer : nil;
}

static void fail(int status, NSString *message) {
    fprintf(stderr, "media-sessions: %s\n", message.UTF8String);
    exit(status);
}

static void loadMediaRemote(void) {
    mr.handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!mr.handle) fail(2, @"MediaRemote yüklenemedi");
    mr.getClients = (GetClientsFn)dlsym(mr.handle, "MRMediaRemoteGetNowPlayingClients");
    mr.localOrigin = (GetLocalOriginFn)dlsym(mr.handle, "MRMediaRemoteGetLocalOrigin");
    mr.createPath = (CreatePathFn)dlsym(mr.handle, "MRNowPlayingPlayerPathCreate");
    mr.infoForPlayer = (InfoForPlayerFn)dlsym(mr.handle, "MRMediaRemoteGetNowPlayingInfoForPlayer");
    mr.stateForPlayer = (StateForPlayerFn)dlsym(mr.handle, "MRMediaRemoteGetPlaybackStateForPlayer");
    mr.supportedCommands = (SupportedCommandsFn)dlsym(mr.handle, "MRMediaRemoteGetSupportedCommandsForPlayer");
    mr.sendToPlayer = (SendToPlayerFn)dlsym(mr.handle, "MRMediaRemoteSendCommandToPlayerWithResult");
    mr.clientPID = (ClientPIDFn)dlsym(mr.handle, "MRNowPlayingClientGetProcessIdentifier");
    mr.clientBundleIdentifier = (ClientStringFn)dlsym(mr.handle, "MRNowPlayingClientGetBundleIdentifier");
    mr.clientParentBundleIdentifier = (ClientStringFn)dlsym(mr.handle, "MRNowPlayingClientGetParentAppBundleIdentifier");
    mr.clientDisplayName = (ClientStringFn)dlsym(mr.handle, "MRNowPlayingClientGetDisplayName");
    mr.registerForNotifications = (RegisterFn)dlsym(mr.handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (!mr.getClients || !mr.localOrigin || !mr.createPath || !mr.infoForPlayer || !mr.stateForPlayer ||
        !mr.sendToPlayer || !mr.clientPID || !mr.clientBundleIdentifier || !mr.registerForNotifications) {
        fail(2, @"MediaRemote işlevleri bulunamadı");
    }
    callbackQueue = dispatch_queue_create("notch.media-sessions.callback", DISPATCH_QUEUE_SERIAL);
}

// MARK: - Eşzamanlı sarmalayıcılar (çağıran kuyruk beklenir, yanıt callbackQueue'dan gelir)

static NSArray *fetchClients(void) {
    __block NSArray *result = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    mr.getClients(callbackQueue, ^(NSArray *clients) {
        result = clients;
        dispatch_semaphore_signal(done);
    });
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, callTimeout));
    return result ?: @[];
}

static id pathForClient(id client) {
    return CFBridgingRelease(mr.createPath(mr.localOrigin(), client, nil));
}

static unsigned int fetchState(id path) {
    __block unsigned int result = 0;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    mr.stateForPlayer(path, callbackQueue, ^(unsigned int state) {
        result = state;
        dispatch_semaphore_signal(done);
    });
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, callTimeout));
    return result;
}

static NSDictionary *fetchInfo(id path, BOOL includeArtwork) {
    __block NSDictionary *result = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    mr.infoForPlayer(path, includeArtwork, callbackQueue, ^(NSDictionary *info) {
        result = info;
        dispatch_semaphore_signal(done);
    });
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, callTimeout));
    return result;
}

/// Etkin komutlar (MRMediaRemoteCommand): arayüz desteklenmeyen düğmeyi soluklaştırır. Okunamazsa nil.
static NSArray<NSNumber *> *fetchSupportedCommands(id path) {
    if (!mr.supportedCommands) return nil;
    __block NSArray *result = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    mr.supportedCommands(path, callbackQueue, ^(NSArray *commands) {
        result = commands;
        dispatch_semaphore_signal(done);
    });
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, callTimeout));
    if (!result) return nil;
    NSMutableArray<NSNumber *> *enabled = [NSMutableArray array];
    for (id command in result) {
        @try {
            if ([[command valueForKey:@"enabled"] boolValue]) [enabled addObject:[command valueForKey:@"command"]];
        } @catch (NSException *exception) {
            return nil;
        }
    }
    [enabled sortUsingSelector:@selector(compare:)];
    return enabled;
}

static id findPath(int pid) {
    for (id client in fetchClients()) {
        if (mr.clientPID(client) == pid) return pathForClient(client);
    }
    return nil;
}

// MARK: - Akış

/// Oturum başına son gönderilen kapak; kapak yalnız değişince satıra eklenir (base64 büyük).
static NSMutableDictionary<NSNumber *, NSData *> *sentArtwork;
static NSMutableDictionary<NSNumber *, NSString *> *artworkTrackKey;
/// Kapak istenince MediaRemote onu oynatıcıdan birkaç saniye sonra getiriyor; parça başına bu süre
/// boyunca her yenilemede yeniden istenir (sayı sınırı bildirim patlamasında hemen tükeniyordu).
static NSMutableDictionary<NSNumber *, NSDate *> *artworkDeadline;
static const NSTimeInterval artworkRetryWindow = 30;
static NSString *lastLine;
static BOOL refreshPending;
static dispatch_queue_t workQueue;

static void putString(NSMutableDictionary *payload, NSString *key, id value) {
    if ([value isKindOfClass:NSString.class] && [(NSString *)value length] > 0) payload[key] = value;
}

static void putMicros(NSMutableDictionary *payload, NSString *key, id value) {
    if ([value isKindOfClass:NSNumber.class]) payload[key] = @((long long)([(NSNumber *)value doubleValue] * 1e6));
}

static NSString *trackKey(NSDictionary *info) {
    return [NSString stringWithFormat:@"%@\x1f%@\x1f%@", info[@"kMRMediaRemoteNowPlayingInfoTitle"] ?: @"",
                                      info[@"kMRMediaRemoteNowPlayingInfoArtist"] ?: @"",
                                      info[@"kMRMediaRemoteNowPlayingInfoAlbum"] ?: @""];
}

/// workQueue'da çalışır: tüm oynatıcıları okur, değiştiyse tek JSON satırı yazar.
static void refreshNow(void) {
    NSMutableArray *sessions = [NSMutableArray array];
    NSMutableDictionary<NSNumber *, id> *artworkChanges = [NSMutableDictionary dictionary];
    NSMutableSet<NSNumber *> *seen = [NSMutableSet set];

    for (id client in fetchClients()) {
        int pid = mr.clientPID(client);
        id path = pathForClient(client);
        NSDictionary *info = fetchInfo(path, NO);
        NSString *title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
        // Bilgisiz istemci (yalnız ses oturumu) ve adaptörün sınama istemcisi listelenmez.
        if (![title isKindOfClass:NSString.class] || title.length == 0) continue;
        if ([info[@"kMRMediaRemoteNowPlayingInfoServiceIdentifier"]
                isEqual:@"com.vandenbe.MediaRemoteAdapter.TestClient"]) continue;
        NSNumber *key = @(pid);
        [seen addObject:key];

        NSMutableDictionary *payload = [NSMutableDictionary dictionary];
        payload[@"processIdentifier"] = key;
        putString(payload, @"bundleIdentifier", mr.clientBundleIdentifier(client));
        if (mr.clientParentBundleIdentifier) {
            putString(payload, @"parentApplicationBundleIdentifier", mr.clientParentBundleIdentifier(client));
        }
        if (mr.clientDisplayName) putString(payload, @"displayName", mr.clientDisplayName(client));
        payload[@"playing"] = @((BOOL)(fetchState(path) == playbackStatePlaying));
        payload[@"title"] = title;
        putString(payload, @"artist", info[@"kMRMediaRemoteNowPlayingInfoArtist"]);
        putString(payload, @"album", info[@"kMRMediaRemoteNowPlayingInfoAlbum"]);
        putMicros(payload, @"durationMicros", info[@"kMRMediaRemoteNowPlayingInfoDuration"]);
        putMicros(payload, @"elapsedTimeMicros", info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]);
        id timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
        if ([timestamp isKindOfClass:NSDate.class]) {
            payload[@"timestampEpochMicros"] = @((long long)([(NSDate *)timestamp timeIntervalSince1970] * 1e6));
        }
        id rate = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
        if ([rate isKindOfClass:NSNumber.class]) payload[@"playbackRate"] = rate;
        id shuffle = info[@"kMRMediaRemoteNowPlayingInfoShuffleMode"];
        if ([shuffle isKindOfClass:NSNumber.class]) payload[@"shuffleMode"] = shuffle;
        id repeat = info[@"kMRMediaRemoteNowPlayingInfoRepeatMode"];
        if ([repeat isKindOfClass:NSNumber.class]) payload[@"repeatMode"] = repeat;
        NSArray *commands = fetchSupportedCommands(path);
        if (commands) payload[@"commands"] = commands;

        // Kapak yalnız parça değişince (ve alınamadıysa 30 sn boyunca) istenir.
        NSString *track = trackKey(info);
        BOOL newTrack = ![artworkTrackKey[key] isEqualToString:track];
        if (newTrack) {
            artworkTrackKey[key] = track;
            artworkDeadline[key] = [NSDate dateWithTimeIntervalSinceNow:artworkRetryWindow];
        }
        if (newTrack || (sentArtwork[key] == nil && artworkDeadline[key].timeIntervalSinceNow > 0)) {
            NSData *artwork = fetchInfo(path, YES)[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
            if (![artwork isKindOfClass:NSData.class]) artwork = nil;
            if (!(artwork == sentArtwork[key] || [artwork isEqualToData:sentArtwork[key]])) {
                artworkChanges[key] = artwork ?: NSNull.null;
                if (artwork) sentArtwork[key] = artwork; else [sentArtwork removeObjectForKey:key];
            }
        }
        [sessions addObject:payload];
    }

    for (NSNumber *key in sentArtwork.allKeys) {
        if (![seen containsObject:key]) [sentArtwork removeObjectForKey:key];
    }
    for (NSNumber *key in artworkTrackKey.allKeys) {
        if (![seen containsObject:key]) {
            [artworkTrackKey removeObjectForKey:key];
            [artworkDeadline removeObjectForKey:key];
        }
    }
    [sessions sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"processIdentifier" ascending:YES]]];

    NSData *body = [NSJSONSerialization dataWithJSONObject:@{@"type": @"sessions", @"sessions": sessions}
                                                   options:NSJSONWritingSortedKeys error:nil];
    NSString *line = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
    if (artworkChanges.count == 0 && [line isEqualToString:lastLine]) return;
    lastLine = line;

    if (artworkChanges.count > 0) {
        for (NSMutableDictionary *payload in sessions) {
            id artwork = artworkChanges[payload[@"processIdentifier"]];
            if (artwork == NSNull.null) payload[@"artworkData"] = NSNull.null;
            else if (artwork) payload[@"artworkData"] = [(NSData *)artwork base64EncodedStringWithOptions:0];
        }
        body = [NSJSONSerialization dataWithJSONObject:@{@"type": @"sessions", @"sessions": sessions} options:0 error:nil];
    }
    fwrite(body.bytes, 1, body.length, stdout);
    fputc('\n', stdout);
    if (fflush(stdout) != 0 || ferror(stdout)) exit(0);
}

/// Bildirim patlamalarını birleştirir (parça geçişinde art arda birkaç bildirim gelir).
static void scheduleRefresh(void) {
    dispatch_async(workQueue, ^{
        if (refreshPending) return;
        refreshPending = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), workQueue, ^{
            refreshPending = NO;
            refreshNow();
        });
    });
}

void sessions_stream(void) {
    loadMediaRemote();
    workQueue = dispatch_queue_create("notch.media-sessions.work", DISPATCH_QUEUE_SERIAL);
    sentArtwork = [NSMutableDictionary dictionary];
    artworkTrackKey = [NSMutableDictionary dictionary];
    artworkDeadline = [NSMutableDictionary dictionary];

    mr.registerForNotifications(callbackQueue);
    BOOL debug = getenv("NOTCH_SESSIONS_DEBUG") != NULL;
    const char *names[] = {
        "kMRMediaRemotePlayerIsPlayingDidChangeNotification",
        "kMRMediaRemotePlayerNowPlayingInfoDidChangeNotification",
        "kMRMediaRemotePlayerPlaybackStateDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
    };
    for (size_t index = 0; index < sizeof(names) / sizeof(names[0]); index++) {
        NSString *name = constantNamed(names[index]);
        if (!name) continue;
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            if (debug) fprintf(stderr, "bildirim: %s\n", note.name.UTF8String);
            scheduleRefresh();
        }];
    }
    [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidTerminateApplicationNotification
                                                                object:nil queue:nil
                                                            usingBlock:^(NSNotification *note) { scheduleRefresh(); }];

    // Güvenlik ağı: kaçan bildirim en geç 5 sn'de yakalanır; uygulama kapandıysa (ebeveyn launchd) çık.
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, workQueue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 5 * NSEC_PER_SEC,
                              NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        if (getppid() == 1) exit(0);
        scheduleRefresh();
    });
    dispatch_resume(timer);

    scheduleRefresh();
    [NSRunLoop.mainRunLoop run];
}

// MARK: - Komutlar

static long long envNumber(const char *name) {
    const char *value = getenv(name);
    if (!value) fail(1, [NSString stringWithFormat:@"%s eksik", name]);
    return strtoll(value, NULL, 10);
}

static void sendAndWait(unsigned int command, NSDictionary *options) {
    int pid = (int)envNumber("NOTCH_SESSIONS_PID");
    id path = findPath(pid);
    if (!path) fail(3, [NSString stringWithFormat:@"%d süreçli oynatıcı bulunamadı", pid]);
    __block NSString *error = nil;
    __block BOOL answered = NO;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    Boolean accepted = mr.sendToPlayer(command, options, path, 0, callbackQueue, ^(id result) {
        answered = YES;
        @try {
            id value = [result valueForKey:@"error"];
            if (value) error = [value description];
        } @catch (NSException *exception) {
        }
        dispatch_semaphore_signal(done);
    });
    if (!accepted) fail(4, @"komut kabul edilmedi");
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, callTimeout));
    if (!answered) fail(5, @"komut yanıtı gelmedi");
    if (error) fail(6, error);
}

/// NOTCH_SESSIONS_PID oynatıcısına komut: 0 oynat, 1 duraklat, 2 oynat/duraklat, 4 sonraki, 5 önceki.
void sessions_send(void) {
    loadMediaRemote();
    long long command = envNumber("NOTCH_SESSIONS_VALUE");
    if (command != 0 && command != 1 && command != 2 && command != 4 && command != 5) {
        fail(1, [NSString stringWithFormat:@"geçersiz komut %lld", command]);
    }
    sendAndWait((unsigned int)command, nil);
}

/// NOTCH_SESSIONS_PID oynatıcısında konum (NOTCH_SESSIONS_VALUE mikrosaniye).
void sessions_seek(void) {
    loadMediaRemote();
    NSString *positionKey = constantNamed("kMRMediaRemoteOptionPlaybackPosition");
    if (!positionKey) fail(2, @"konum seçeneği bulunamadı");
    double seconds = envNumber("NOTCH_SESSIONS_VALUE") / 1e6;
    sendAndWait(seekCommand, @{positionKey: @(seconds)});
}
