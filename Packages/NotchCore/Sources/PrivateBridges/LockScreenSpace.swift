import CoreFoundation
import Darwin

/// ⚠️ Private API (SkyLight): kilit ekranının üstünde duran pencere Space'i. Public bir yolu yok.
/// Riskler (araştırma raporu): macOS 27'de `SLSShowSpaces` dönüş değeri anlamını yitirdi, bazı
/// uygulamalarda kilitlenirken çökme ve bir betada WindowServer çökmesi görüldü. Bu yüzden:
/// semboller çalışma anında çözülür, biri eksikse özellik kapanır; dönüş değerlerine güvenilmez;
/// Space ilk kilitte bir kez kurulur ve pencere yalnız kilit süresince içinde tutulur.
@MainActor
public final class LockScreenSpace {
    /// CGS Space mutlak seviyeleri: ekran kilidi 300, kilitteki bildirimler 400. Kilidin hemen üstü.
    private static let absoluteLevel: Int32 = 400

    private typealias MainConnectionFunction = @convention(c) () -> Int32
    private typealias SpaceCreateFunction = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias SpaceLevelFunction = @convention(c) (Int32, UInt64, Int32) -> Void
    private typealias SpacesFunction = @convention(c) (Int32, CFArray) -> Void
    private typealias WindowsSpacesFunction = @convention(c) (Int32, CFArray, CFArray) -> Void
    private typealias SpaceDestroyFunction = @convention(c) (Int32, UInt64) -> Void

    private struct Symbols {
        let mainConnection: MainConnectionFunction
        let spaceCreate: SpaceCreateFunction
        let setAbsoluteLevel: SpaceLevelFunction
        let showSpaces: SpacesFunction
        let addWindows: WindowsSpacesFunction
        let removeWindows: WindowsSpacesFunction
        let spaceDestroy: SpaceDestroyFunction
    }

    private static func loadSymbols() -> Symbols? {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        guard let mainConnection = symbol("SLSMainConnectionID", as: MainConnectionFunction.self),
              let spaceCreate = symbol("SLSSpaceCreate", as: SpaceCreateFunction.self),
              let setAbsoluteLevel = symbol("SLSSpaceSetAbsoluteLevel", as: SpaceLevelFunction.self),
              let showSpaces = symbol("SLSShowSpaces", as: SpacesFunction.self),
              let addWindows = symbol("SLSAddWindowsToSpaces", as: WindowsSpacesFunction.self),
              let removeWindows = symbol("SLSRemoveWindowsFromSpaces", as: WindowsSpacesFunction.self),
              let spaceDestroy = symbol("SLSSpaceDestroy", as: SpaceDestroyFunction.self) else { return nil }
        return Symbols(mainConnection: mainConnection, spaceCreate: spaceCreate,
                       setAbsoluteLevel: setAbsoluteLevel, showSpaces: showSpaces, addWindows: addWindows,
                       removeWindows: removeWindows, spaceDestroy: spaceDestroy)
    }

    private let symbols: Symbols
    private let connection: Int32
    private var space: UInt64 = 0
    private var attached: Set<Int> = []

    /// Sembollerden biri yoksa nil; çağıran özelliği kullanılamaz gösterir.
    public init?() {
        guard let symbols = Self.loadSymbols() else { return nil }
        self.symbols = symbols
        connection = symbols.mainConnection()
        guard connection != 0 else { return nil }
    }

    /// Pencereyi kilit Space'ine ekler. Space ilk çağrıda kurulur; kurulamazsa false.
    public func attach(windowNumber: Int) -> Bool {
        guard windowNumber > 0, prepareSpace() else { return false }
        guard !attached.contains(windowNumber) else { return true }
        symbols.addWindows(connection, [windowNumber] as CFArray, [space] as CFArray)
        attached.insert(windowNumber)
        return true
    }

    public func detach(windowNumber: Int) {
        guard space != 0, attached.remove(windowNumber) != nil else { return }
        symbols.removeWindows(connection, [windowNumber] as CFArray, [space] as CFArray)
    }

    /// Önce pencereler çıkarılır; Space süreç kapanınca WindowServer tarafından da temizlenir.
    public func invalidate() {
        for window in attached { detach(windowNumber: window) }
        guard space != 0 else { return }
        symbols.spaceDestroy(connection, space)
        space = 0
    }

    private func prepareSpace() -> Bool {
        if space != 0 { return true }
        let created = symbols.spaceCreate(connection, 1, nil)
        guard created != 0 else { return false }
        space = created
        symbols.setAbsoluteLevel(connection, created, Self.absoluteLevel)
        // macOS 27: dönüş değeri her çalıştırmada farklı ve sıfır dışı; bilerek okunmuyor.
        symbols.showSpaces(connection, [created] as CFArray)
        return true
    }
}
