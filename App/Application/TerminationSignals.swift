import AppKit

/// `kill`/`pkill` (SIGTERM), terminalde ⌃C (SIGINT) ve kapanan terminal (SIGHUP) varsayılan olarak süreci
/// anında bitirir: `applicationWillTerminate` çalışmaz, Now Playing yardımcıları (perl) ebeveyni 1 olan
/// yetimler olarak kalır. Sinyal ana kuyrukta yakalanıp normal çıkış yolu (`NSApp.terminate` →
/// `coordinator.stop`) işletilir. `kill -9` yakalanamaz; onun yetimlerini açılışta `OrphanedHelpers` kapatır.
@MainActor
enum TerminationSignals {
    private static var sources: [DispatchSourceSignal] = []

    static func install() {
        guard sources.isEmpty else { return }
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            // Varsayılan eylem kalkmazsa süreç, kaynak tetiklenmeden ölür.
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    AppLog.coordinator.notice("sinyal \(signalNumber) alındı, uygulama kapanıyor")
                    NSApp.terminate(nil)
                }
            }
            source.resume()
            sources.append(source)
        }
    }
}
