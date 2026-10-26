import Foundation

/// The small slice of OSC that TotalMix speaks: int32, float32, string and
/// true/false arguments, plus bundles.
enum OSCValue: Equatable {
    case int(Int32)
    case float(Float)
    case string(String)
    case bool(Bool)

    var number: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .float(let f): return Double(f)
        case .bool(let b): return b ? 1 : 0
        case .string(let s): return Double(s)
        }
    }

    var text: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

struct OSCMessage {
    let address: String
    let args: [OSCValue]

    var number: Double? { args.first?.number }
    var text: String? { args.first?.text }

    func encoded() -> Data {
        var data = Self.padded(address)
        var tags = ","
        var payload = Data()
        for arg in args {
            switch arg {
            case .int(let i):
                tags += "i"
                withUnsafeBytes(of: i.bigEndian) { payload.append(contentsOf: $0) }
            case .float(let f):
                tags += "f"
                withUnsafeBytes(of: f.bitPattern.bigEndian) { payload.append(contentsOf: $0) }
            case .string(let s):
                tags += "s"
                payload.append(Self.padded(s))
            case .bool(let b):
                tags += b ? "T" : "F"
            }
        }
        data.append(Self.padded(tags))
        data.append(payload)
        return data
    }

    private static func padded(_ s: String) -> Data {
        var d = Data(s.utf8)
        d.append(0)
        while d.count % 4 != 0 { d.append(0) }
        return d
    }

    /// Decodes a packet (a message or a bundle of them). Malformed parts are
    /// skipped rather than thrown, since one bad packet shouldn't stop the stream.
    static func decode(_ data: Data) -> [OSCMessage] {
        let bytes = [UInt8](data)
        var out: [OSCMessage] = []
        decode(bytes[...], into: &out)
        return out
    }

    private static func decode(_ b: ArraySlice<UInt8>, into out: inout [OSCMessage]) {
        let base = b.startIndex
        if b.count >= 16, b.starts(with: Array("#bundle".utf8) + [0]) {
            var i = base + 16
            while i + 4 <= b.endIndex {
                let size = Int(readInt(b, i))
                i += 4
                guard size > 0, i + size <= b.endIndex else { return }
                decode(b[i..<(i + size)], into: &out)
                i += size
            }
            return
        }
        var i = base
        guard let address = readString(b, &i), address.hasPrefix("/") else { return }
        guard i < b.endIndex, let tags = readString(b, &i), tags.hasPrefix(",") else {
            out.append(OSCMessage(address: address, args: []))
            return
        }
        var args: [OSCValue] = []
        for tag in tags.dropFirst() {
            switch tag {
            case "i":
                guard i + 4 <= b.endIndex else { return }
                args.append(.int(readInt(b, i))); i += 4
            case "f":
                guard i + 4 <= b.endIndex else { return }
                args.append(.float(Float(bitPattern: UInt32(bitPattern: readInt(b, i))))); i += 4
            case "s":
                guard let s = readString(b, &i) else { return }
                args.append(.string(s))
            case "T": args.append(.bool(true))
            case "F": args.append(.bool(false))
            default: return
            }
        }
        out.append(OSCMessage(address: address, args: args))
    }

    private static func readInt(_ b: ArraySlice<UInt8>, _ i: Int) -> Int32 {
        Int32(bitPattern: UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3]))
    }

    private static func readString(_ b: ArraySlice<UInt8>, _ i: inout Int) -> String? {
        guard let end = b[i...].firstIndex(of: 0) else { return nil }
        let s = String(decoding: b[i..<end], as: UTF8.self)
        // Padding is relative to the slice start for nested bundle elements.
        let rel = end - b.startIndex
        i = b.startIndex + (rel / 4 + 1) * 4
        return s
    }
}

/// One UDP socket: listens on `listenPort` for TotalMix's replies and sends
/// commands to `host:sendPort`.
final class OSCTransport {
    var onMessages: ([OSCMessage]) -> Void = { _ in }
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private var destination = sockaddr_in()
    private let queue = DispatchQueue(label: "mixbar.osc")

    deinit { close() }

    /// Throws an AppError (MB-201/202) when the port can't be opened.
    func open(host: String, sendPort: UInt16, listenPort: UInt16) throws {
        close()
        let s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard s >= 0 else { throw AppError(.socketFailed, String(cString: strerror(errno))) }

        var local = sockaddr_in()
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = listenPort.bigEndian
        local.sin_addr.s_addr = inet_addr("127.0.0.1")
        // Bind to every interface when TotalMix runs on another computer.
        if host != "127.0.0.1" && host != "localhost" { local.sin_addr.s_addr = INADDR_ANY }
        let bound = withUnsafePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let reason = String(cString: strerror(errno))
            Darwin.close(s)
            throw AppError(.portInUse, "UDP port \(listenPort): \(reason)")
        }

        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = sendPort.bigEndian
        let resolved = host == "localhost" ? "127.0.0.1" : host
        guard inet_pton(AF_INET, resolved, &dest.sin_addr) == 1 else {
            Darwin.close(s)
            throw AppError(.badHost, host)
        }
        destination = dest
        fd = s

        let src = DispatchSource.makeReadSource(fileDescriptor: s, queue: queue)
        src.setEventHandler { [weak self] in self?.receive() }
        src.setCancelHandler { Darwin.close(s) }
        src.resume()
        source = src
    }

    func close() {
        source?.cancel()
        source = nil
        fd = -1
    }

    func send(_ message: OSCMessage) {
        guard fd >= 0 else { return }
        let data = message.encoded()
        var dest = destination
        let fd = self.fd
        queue.async {
            _ = data.withUnsafeBytes { buf in
                withUnsafePointer(to: &dest) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, buf.baseAddress, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }
    }

    private func receive() {
        var buffer = [UInt8](repeating: 0, count: 65536)
        var batch: [OSCMessage] = []
        while true {
            let n = recv(fd, &buffer, buffer.count, MSG_DONTWAIT)
            if n <= 0 { break }
            batch += OSCMessage.decode(Data(buffer[0..<n]))
        }
        if !batch.isEmpty { onMessages(batch) }
    }
}
