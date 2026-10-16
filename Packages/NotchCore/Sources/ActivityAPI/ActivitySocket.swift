import Darwin
import Foundation

enum UnixSocket {
    enum SocketError: Error, CustomStringConvertible {
        case pathTooLong
        case system(String, Int32)
        case alreadyRunning

        var description: String {
            switch self {
            case .pathTooLong: APILanguage.current.text("soket yolu çok uzun", "the socket path is too long")
            case let .system(call, code): "\(call): \(String(cString: strerror(code)))"
            case .alreadyRunning: APILanguage.current.text("başka bir örnek bu soketi dinliyor", "another instance is listening on this socket")
            }
        }
    }

    static func address(for path: String) throws(SocketError) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw .pathTooLong }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }

    static func connect(to path: String, timeout: TimeInterval) throws(SocketError) -> Int32 {
        var address = try address(for: path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .system("socket", errno) }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var interval = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &interval, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &interval, socklen_t(MemoryLayout<timeval>.size))
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            close(fd)
            throw .system("connect", code)
        }
        return fd
    }

    static func writeAll(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += written
            }
            return true
        }
    }
}

/// `notch` aracı ve testler için eşzamanlı istemci: bir istek, bir yanıt.
public enum ActivitySocketClient {
    public enum ClientError: Error, Equatable, CustomStringConvertible {
        case notRunning
        case io(String)
        case badResponse

        public var description: String { description(in: .current) }

        public func description(in language: APILanguage) -> String {
            switch self {
            case .notRunning:
                language.text("Browline çalışmıyor ya da etkinlik API'si kapalı (Ayarlar › Şimdi)",
                              "Browline isn't running or its activity API is off (Settings › Now)")
            case let .io(message): language.text("iletişim hatası: \(message)", "communication error: \(message)")
            case .badResponse: language.text("uygulamadan anlaşılmayan yanıt", "unreadable response from the app")
            }
        }
    }

    public static func send(_ request: ActivityRequest, socketURL: URL = ActivityAPI.defaultSocketURL,
                            timeout: TimeInterval = 3) throws(ClientError) -> ActivityResponse {
        let fd: Int32
        do {
            fd = try UnixSocket.connect(to: socketURL.path, timeout: timeout)
        } catch {
            throw .notRunning
        }
        defer { close(fd) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(request) else { throw .io(APILanguage.current.text("istek kodlanamadı", "the request could not be encoded")) }
        line.append(0x0A)
        guard UnixSocket.writeAll(line, to: fd) else { throw .io(String(cString: strerror(errno))) }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while !buffer.contains(0x0A) {
            let count = read(fd, &chunk, chunk.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw .io(count == 0 ? APILanguage.current.text("bağlantı kapandı", "connection closed")
                                              : APILanguage.current.text("zaman aşımı", "timed out")) }
            buffer.append(contentsOf: chunk[0..<count])
            guard buffer.count <= ActivityAPI.maximumLineBytes * 4 else { throw .badResponse }
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let end = buffer.firstIndex(of: 0x0A),
              let response = try? decoder.decode(ActivityResponse.self, from: buffer[..<end]) else {
            throw .badResponse
        }
        return response
    }

    static func isServerAlive(at url: URL) -> Bool {
        guard let fd = try? UnixSocket.connect(to: url.path, timeout: 0.5) else { return false }
        close(fd)
        return true
    }
}

/// Yerel Unix soketi sunucusu. Soket dosyası 0600, klasörü 0700; ayrıca bağlanan sürecin kullanıcı
/// kimliği getpeereid ile denetlenir. Boşta yalnız dinleyen bir DispatchSource var; süreci uyandırmaz.
public final class ActivitySocketServer: @unchecked Sendable {
    public typealias Handler = @Sendable (ActivityRequest) async -> ActivityResponse

    private final class Connection {
        let fd: Int32
        var buffer = Data()
        var source: DispatchSourceRead?
        var pendingResponses = 0
        var readClosed = false
        var isSuspended = false
        /// Yanıt bekleyen istek görevleri; istemci bağlantıyı kapatınca iptal edilir (ask sorusu düşer).
        var tasks: [Int: Task<Void, Never>] = [:]
        var nextTaskID = 0

        init(fd: Int32) { self.fd = fd }
    }

    public let socketURL: URL
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.talatozcoban.browline.activity-api")
    // Aşağıdakiler yalnız `queue` üzerinde değişir.
    private var listenSource: DispatchSourceRead?
    private var connections: [Int32: Connection] = [:]
    private static let maximumConnections = 16

    public init(socketURL: URL = ActivityAPI.defaultSocketURL, handler: @escaping Handler) {
        self.socketURL = socketURL
        self.handler = handler
    }

    public func start() throws {
        try queue.sync { try startOnQueue() }
    }

    public func stop() {
        queue.sync {
            listenSource?.cancel()
            listenSource = nil
            for connection in connections.values {
                connection.tasks.values.forEach { $0.cancel() }
                if connection.isSuspended { connection.source?.resume() }
                connection.source?.cancel()
            }
            connections.removeAll()
            unlink(socketURL.path)
        }
    }

    private func startOnQueue() throws {
        guard listenSource == nil else { return }
        let directory = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        chmod(directory.path, 0o700)
        // Çökmüş önceki süreçten kalan soket dosyası silinir; canlı bir örnek varsa dokunulmaz.
        if ActivitySocketClient.isServerAlive(at: socketURL) { throw UnixSocket.SocketError.alreadyRunning }
        unlink(socketURL.path)

        var address = try UnixSocket.address(for: socketURL.path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UnixSocket.SocketError.system("socket", errno) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(socketURL.path, 0o600) == 0, listen(fd, 8) == 0 else {
            let code = errno
            close(fd)
            throw UnixSocket.SocketError.system("bind/listen", code)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptConnections(on: fd) }
        source.setCancelHandler { close(fd) }
        source.resume()
        listenSource = source
    }

    private func acceptConnections(on listener: Int32) {
        while true {
            let fd = accept(listener, nil, nil)
            guard fd >= 0 else { return }  // EAGAIN: bekleyen bağlantı kalmadı
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(fd, &uid, &gid) == 0, uid == getuid(),
                  connections.count < Self.maximumConnections else {
                close(fd)
                continue
            }
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            var noSigPipe: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            let connection = Connection(fd: fd)
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.readAvailable(fd: fd) }
            source.setCancelHandler { close(fd) }
            connection.source = source
            connections[fd] = connection
            source.resume()
        }
    }

    private func readAvailable(fd: Int32) {
        guard let connection = connections[fd] else { return }
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(connection.fd, &chunk, chunk.count)
            if count > 0 {
                connection.buffer.append(contentsOf: chunk[0..<count])
                // Satırsız akış belleği büyütmesin: tampon dolunca işle; kalan veri için kaynak yeniden tetiklenir.
                if connection.buffer.count > ActivityAPI.maximumLineBytes { break }
                continue
            }
            if count < 0, errno == EAGAIN || errno == EINTR { break }
            // 0 = istemci yazmayı bitirdi; bekleyen yanıtlar gönderildikten sonra kapatılır. Yanıt bekleyen
            // uzun istekler (ask) iptal edilir: istemci gittiyse soru notch'ta kalmasın.
            connection.tasks.values.forEach { $0.cancel() }
            markReadClosed(connection)
            break
        }
        processLines(connection)
        closeIfDone(connection)
    }

    private func processLines(_ connection: Connection) {
        while let newline = connection.buffer.firstIndex(of: 0x0A) {
            let line = connection.buffer[connection.buffer.startIndex..<newline]
            connection.buffer.removeSubrange(connection.buffer.startIndex...newline)
            guard !line.isEmpty else { continue }
            let decoder = JSONDecoder()
            guard let request = try? decoder.decode(ActivityRequest.self, from: Data(line)) else {
                write(.failure(APILanguage.current.text("geçersiz istek: satır başına bir JSON nesnesi bekleniyor",
                                                         "invalid request: expected one JSON object per line")), to: connection)
                continue
            }
            connection.pendingResponses += 1
            let handler = handler
            let fd = connection.fd
            let taskID = connection.nextTaskID
            connection.nextTaskID += 1
            connection.tasks[taskID] = Task { [weak self] in
                let response = await handler(request)
                guard let server = self else { return }
                server.queue.async {
                    guard let connection = server.connections[fd] else { return }
                    connection.tasks.removeValue(forKey: taskID)
                    connection.pendingResponses -= 1
                    server.write(response, to: connection)
                    server.closeIfDone(connection)
                }
            }
        }
        if connection.buffer.count > ActivityAPI.maximumLineBytes {
            write(.failure(APILanguage.current.text("satır çok uzun", "line too long")), to: connection)
            connection.buffer.removeAll()
            markReadClosed(connection)
        }
    }

    private func write(_ response: ActivityResponse, to connection: Connection) {
        guard connections[connection.fd] != nil else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(response) else { return }
        data.append(0x0A)
        _ = UnixSocket.writeAll(data, to: connection.fd)
    }

    /// Okuma kaynağını bir kez askıya alır; askıda değilken resume çağırmak libdispatch'i çökertir.
    private func markReadClosed(_ connection: Connection) {
        connection.readClosed = true
        guard !connection.isSuspended else { return }
        connection.isSuspended = true
        connection.source?.suspend()
    }

    private func closeIfDone(_ connection: Connection) {
        guard connection.readClosed, connection.pendingResponses == 0,
              connections.removeValue(forKey: connection.fd) != nil else { return }
        // Askıdaki kaynak iptal edilmeden önce sürdürülmeli; yoksa iptal işleyicisi çalışmaz.
        if connection.isSuspended {
            connection.isSuspended = false
            connection.source?.resume()
        }
        connection.source?.cancel()
    }
}
