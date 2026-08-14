#if os(macOS)
import Compression
import Foundation

struct SimpleZIPArchiveReader {
    enum Error: Swift.Error {
        case invalidArchive
        case unsupportedFeature
        case entryTooLarge
    }

    struct Entry {
        var path: String
        var flags: UInt16
        var method: UInt16
        var compressedSize: UInt32
        var uncompressedSize: UInt32
        var localHeaderOffset: UInt32
    }

    private let archive: Data
    private let entries: [String: Entry]

    var paths: [String] { Array(entries.keys) }

    init(url: URL, maximumArchiveBytes: Int = 100 * 1_024 * 1_024) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let size = values.fileSize,
              size <= maximumArchiveBytes else {
            throw Error.invalidArchive
        }
        let archive = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let endOffset = Self.endOfCentralDirectory(in: archive) else {
            throw Error.invalidArchive
        }
        let diskNumber = try archive.uint16(at: endOffset + 4)
        let centralDisk = try archive.uint16(at: endOffset + 6)
        let entryCount = try archive.uint16(at: endOffset + 10)
        let centralSize = try archive.uint32(at: endOffset + 12)
        let centralOffset = try archive.uint32(at: endOffset + 16)
        guard diskNumber == 0, centralDisk == 0,
              Int(centralOffset) + Int(centralSize) <= archive.count else {
            throw Error.unsupportedFeature
        }

        var parsed: [String: Entry] = [:]
        var cursor = Int(centralOffset)
        for _ in 0..<Int(entryCount) {
            guard try archive.uint32(at: cursor) == 0x0201_4b50 else {
                throw Error.invalidArchive
            }
            let flags = try archive.uint16(at: cursor + 8)
            let method = try archive.uint16(at: cursor + 10)
            let compressedSize = try archive.uint32(at: cursor + 20)
            let uncompressedSize = try archive.uint32(at: cursor + 24)
            let nameLength = Int(try archive.uint16(at: cursor + 28))
            let extraLength = Int(try archive.uint16(at: cursor + 30))
            let commentLength = Int(try archive.uint16(at: cursor + 32))
            let localOffset = try archive.uint32(at: cursor + 42)
            let nameStart = cursor + 46
            let next = nameStart + nameLength + extraLength + commentLength
            guard next <= archive.count,
                  compressedSize != UInt32.max,
                  uncompressedSize != UInt32.max,
                  let path = String(data: archive[nameStart..<(nameStart + nameLength)], encoding: .utf8),
                  !path.isEmpty else {
                throw Error.invalidArchive
            }
            if !path.hasSuffix("/") {
                parsed[path] = Entry(
                    path: path,
                    flags: flags,
                    method: method,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localOffset
                )
            }
            cursor = next
        }
        self.archive = archive
        self.entries = parsed
    }

    func contains(_ path: String) -> Bool { entries[path] != nil }

    func data(for path: String, maximumUncompressedBytes: UInt64) throws -> Data? {
        guard let entry = entries[path] else { return nil }
        guard UInt64(entry.uncompressedSize) <= maximumUncompressedBytes else {
            throw Error.entryTooLarge
        }
        guard entry.flags & 0x0001 == 0 else { throw Error.unsupportedFeature }
        let header = Int(entry.localHeaderOffset)
        guard try archive.uint32(at: header) == 0x0403_4b50 else {
            throw Error.invalidArchive
        }
        let nameLength = Int(try archive.uint16(at: header + 26))
        let extraLength = Int(try archive.uint16(at: header + 28))
        let dataStart = header + 30 + nameLength + extraLength
        let dataEnd = dataStart + Int(entry.compressedSize)
        guard dataStart >= 0, dataEnd <= archive.count else { throw Error.invalidArchive }
        let compressed = Data(archive[dataStart..<dataEnd])
        switch entry.method {
        case 0:
            guard compressed.count == Int(entry.uncompressedSize) else {
                throw Error.invalidArchive
            }
            return compressed
        case 8:
            return try Self.inflate(compressed, expectedSize: Int(entry.uncompressedSize))
        default:
            throw Error.unsupportedFeature
        }
    }

    private static func endOfCentralDirectory(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let lowerBound = max(0, data.count - 65_557)
        for offset in stride(from: data.count - 22, through: lowerBound, by: -1) {
            if (try? data.uint32(at: offset)) == 0x0605_4b50 { return offset }
        }
        return nil
    }

    private static func inflate(_ source: Data, expectedSize: Int) throws -> Data {
        if expectedSize == 0 { return Data() }
        guard !source.isEmpty else { throw Error.invalidArchive }
        var output = Data(count: expectedSize + 1)
        let outputCapacity = output.count
        let placeholder = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        defer { placeholder.deallocate() }
        var stream = compression_stream(
            dst_ptr: placeholder,
            dst_size: 0,
            src_ptr: UnsafePointer(placeholder),
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
                != COMPRESSION_STATUS_ERROR else {
            throw Error.invalidArchive
        }
        defer { compression_stream_destroy(&stream) }

        let status = try source.withUnsafeBytes { sourceBuffer in
            guard let sourceAddress = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw Error.invalidArchive
            }
            return try output.withUnsafeMutableBytes { outputBuffer in
                guard let outputAddress = outputBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    throw Error.invalidArchive
                }
                stream.src_ptr = sourceAddress
                stream.src_size = source.count
                stream.dst_ptr = outputAddress
                stream.dst_size = outputCapacity
                return compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
            }
        }
        let written = outputCapacity - stream.dst_size
        guard status == COMPRESSION_STATUS_END, written == expectedSize else {
            throw Error.invalidArchive
        }
        output.count = written
        return output
    }
}

private extension Data {
    func uint16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else {
            throw SimpleZIPArchiveReader.Error.invalidArchive
        }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else {
            throw SimpleZIPArchiveReader.Error.invalidArchive
        }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
#endif
