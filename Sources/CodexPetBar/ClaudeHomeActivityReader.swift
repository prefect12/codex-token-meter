import Foundation

/// Reads Claude Desktop's locally persisted Home conversation-list cache.
///
/// Claude Desktop stores the dehydrated TanStack Query state for claude.ai in
/// IndexedDB. Chromium externalizes large IndexedDB values into `.blob` files
/// and may Snappy-compress them. This reader only extracts conversation-list
/// metadata; it does not read cookies, call claude.ai, or retain message bodies.
final class ClaudeHomeActivityReader {
    private struct BlobCandidate {
        let url: URL
        let size: Int
        let modifiedAt: Date

        var signature: String {
            "\(url.path)|\(size)|\(modifiedAt.timeIntervalSince1970)"
        }
    }

    private let fileManager = FileManager.default
    private let blobRoot: URL
    private var cachedSignature: String?
    private var cachedItems: [CodexThreadItem] = []

    init(blobRoot: URL? = nil) {
        self.blobRoot = blobRoot
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/Claude/IndexedDB", isDirectory: true)
                .appendingPathComponent("https_claude.ai_0.indexeddb.blob", isDirectory: true)
    }

    func read(limit: Int, cutoff: Date) -> [CodexThreadItem] {
        let candidates = recentBlobCandidates(limit: 8)
        guard !candidates.isEmpty else { return [] }

        let signature = candidates.map(\.signature).joined(separator: "\n")
        if signature == cachedSignature {
            return cachedItems
                .filter { $0.lastActivity >= cutoff }
                .prefix(max(0, limit))
                .map { $0 }
        }

        var byID: [String: CodexThreadItem] = [:]
        for candidate in candidates {
            guard let data = try? Data(contentsOf: candidate.url, options: [.mappedIfSafe]) else {
                continue
            }
            let root: ClaudeHomeV8Value
            do {
                root = try ClaudeHomeV8Decoder.decodeIndexedDBBlob(data)
            } catch {
                if ProcessInfo.processInfo.environment["TASKBAR_CLAUDE_HOME_DEBUG"] == "1" {
                    FileHandle.standardError.write(Data("Claude Home decode: \(error)\n".utf8))
                }
                continue
            }
            guard case .object(let rootObject) = root,
                  rootObject.stringProperty("buster")?.hasPrefix("conversations_v2:") == true else {
                continue
            }

            var visited = Set<ObjectIdentifier>()
            var objects: [ClaudeHomeV8Object] = []
            collectConversationObjects(in: root, visited: &visited, output: &objects)
            for object in objects {
                guard let item = threadItem(from: object) else { continue }
                if let existing = byID[item.id], existing.lastActivity >= item.lastActivity {
                    continue
                }
                byID[item.id] = item
            }
        }

        let items = byID.values
            .sorted(by: stableThreadOrder)
        cachedSignature = signature
        cachedItems = items
        return items
            .filter { $0.lastActivity >= cutoff }
            .prefix(max(0, limit))
            .map { $0 }
    }

    private func recentBlobCandidates(limit: Int) -> [BlobCandidate] {
        guard let enumerator = fileManager.enumerator(
            at: blobRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var candidates: [BlobCandidate] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
            ),
            values.isRegularFile == true,
            let size = values.fileSize,
            size >= 3,
            size <= ClaudeHomeV8Decoder.maximumCompressedBytes else {
                continue
            }
            candidates.append(BlobCandidate(
                url: url,
                size: size,
                modifiedAt: values.contentModificationDate ?? .distantPast
            ))
        }
        return candidates
            .sorted {
                if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
                return $0.url.path < $1.url.path
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    private func collectConversationObjects(
        in value: ClaudeHomeV8Value,
        visited: inout Set<ObjectIdentifier>,
        output: inout [ClaudeHomeV8Object]
    ) {
        switch value {
        case .object(let object):
            guard visited.insert(ObjectIdentifier(object)).inserted else { return }
            if object.stringProperty("uuid") != nil,
               object.stringProperty("name") != nil,
               object.stringProperty("updated_at") != nil,
               object.properties["current_leaf_message_uuid"] != nil {
                output.append(object)
            }
            for nested in object.properties.values {
                collectConversationObjects(in: nested, visited: &visited, output: &output)
            }
        case .array(let array):
            guard visited.insert(ObjectIdentifier(array)).inserted else { return }
            for nested in array.values {
                collectConversationObjects(in: nested, visited: &visited, output: &output)
            }
            for nested in array.properties.values {
                collectConversationObjects(in: nested, visited: &visited, output: &output)
            }
        default:
            break
        }
    }

    private func threadItem(from object: ClaudeHomeV8Object) -> CodexThreadItem? {
        guard let id = object.stringProperty("uuid"),
              UUID(uuidString: id) != nil,
              let updatedAtText = object.stringProperty("updated_at"),
              let updatedAt = iso8601Date(updatedAtText) else {
            return nil
        }
        let title = cleanTitle(object.stringProperty("name"))
            ?? cleanTitle(object.stringProperty("summary"))
            ?? String(id.prefix(8))
        let preview = cleanPreview(object.stringProperty("summary"))
        return CodexThreadItem(
            id: "claude-home:\(id)",
            title: title,
            preview: preview,
            cwd: nil,
            lastActivity: updatedAt,
            startedAt: nil,
            externalReadAt: nil,
            status: .unread,
            turns: 1,
            compressionCount: nil,
            source: "claude-home",
            isExplicitUnread: false,
            codexUpdatedAt: nil,
            tokensUsed: nil,
            tokenBreakdown: TokenBreakdown(),
            model: object.stringProperty("model"),
            threadKind: .root,
            parentThreadID: nil,
            agentNickname: nil,
            agentPath: nil,
            plan: nil
        )
    }
}

private enum ClaudeHomeV8Value {
    case undefined
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case object(ClaudeHomeV8Object)
    case array(ClaudeHomeV8Array)

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }
}

private final class ClaudeHomeV8Object {
    var properties: [String: ClaudeHomeV8Value] = [:]

    func stringProperty(_ key: String) -> String? {
        properties[key]?.stringValue
    }
}

private final class ClaudeHomeV8Array {
    var values: [ClaudeHomeV8Value]
    var properties: [String: ClaudeHomeV8Value] = [:]

    init(count: Int) {
        values = Array(repeating: .undefined, count: count)
    }
}

private enum ClaudeHomeV8DecodeError: Error {
    case invalidFormat
    case unsupportedTag(UInt8)
    case truncated
    case sizeLimit
    case invalidReference
}

private struct ClaudeHomeV8Decoder {
    static let maximumCompressedBytes = 32 * 1024 * 1024
    private static let maximumExpandedBytes = 64 * 1024 * 1024
    private static let maximumContainerEntries = 250_000
    private static let maximumDepth = 256

    private var bytes: [UInt8]
    private var offset = 0
    private var version = 0
    private var references: [ClaudeHomeV8Value] = []

    static func decodeIndexedDBBlob(_ data: Data) throws -> ClaudeHomeV8Value {
        guard data.count <= maximumCompressedBytes else {
            throw ClaudeHomeV8DecodeError.sizeLimit
        }
        var bytes = [UInt8](data)
        if bytes.starts(with: [0xff, 0x11, 0x02]) {
            bytes = try decompressSnappy(Array(bytes.dropFirst(3)))
        }
        guard bytes.count <= maximumExpandedBytes else {
            throw ClaudeHomeV8DecodeError.sizeLimit
        }

        let searchLimit = min(64, max(0, bytes.count - 1))
        guard let headerOffset = (0..<searchLimit).first(where: { index in
            bytes[index] == 0xff && bytes[index + 1] >= 13 && bytes[index + 1] <= 20
        }) else {
            throw ClaudeHomeV8DecodeError.invalidFormat
        }
        var decoder = ClaudeHomeV8Decoder(bytes: Array(bytes.dropFirst(headerOffset)))
        return try decoder.decode()
    }

    private mutating func decode() throws -> ClaudeHomeV8Value {
        guard try readTag() == 0xff else {
            throw ClaudeHomeV8DecodeError.invalidFormat
        }
        version = Int(try readVarint())
        guard version >= 13, version <= 20 else {
            throw ClaudeHomeV8DecodeError.invalidFormat
        }
        return try readValue(depth: 0)
    }

    private mutating func readValue(depth: Int) throws -> ClaudeHomeV8Value {
        guard depth <= Self.maximumDepth else {
            throw ClaudeHomeV8DecodeError.sizeLimit
        }
        let tag = try readTag()
        let value: ClaudeHomeV8Value
        switch tag {
        case 0x2d, 0x5f: // hole, undefined
            value = .undefined
        case 0x30:
            value = .null
        case 0x54:
            value = .bool(true)
        case 0x46:
            value = .bool(false)
        case 0x49:
            value = .int(try readZigZag())
        case 0x55:
            value = .int(Int64(try readVarint()))
        case 0x4e:
            value = .double(try readDouble())
        case 0x5a:
            value = try readBigInt()
        case 0x53:
            value = .string(try readString(encoding: .utf8))
        case 0x22:
            value = .string(try readString(encoding: .isoLatin1))
        case 0x63:
            value = .string(try readString(encoding: .utf16LittleEndian))
        case 0x5e:
            let id = Int(try readVarint())
            guard references.indices.contains(id) else {
                throw ClaudeHomeV8DecodeError.invalidReference
            }
            value = references[id]
        case 0x6f:
            value = try readObject(depth: depth + 1)
        case 0x41:
            value = try readDenseArray(depth: depth + 1)
        case 0x61:
            value = try readSparseArray(depth: depth + 1)
        case 0x44:
            value = .double(try readDouble())
            references.append(value)
        case 0x78:
            value = .bool(false)
            references.append(value)
        case 0x79:
            value = .bool(true)
            references.append(value)
        case 0x6e:
            value = .double(try readDouble())
            references.append(value)
        case 0x73:
            value = .string(try readValue(depth: depth + 1).stringValue ?? "")
            references.append(value)
        case 0x7a:
            value = try readBigInt()
            references.append(value)
        case 0x52:
            let pattern = try readValue(depth: depth + 1).stringValue ?? ""
            _ = try readVarint()
            value = .string(pattern)
            references.append(value)
        case 0x3b:
            value = try readMap(depth: depth + 1)
        case 0x27:
            value = try readSet(depth: depth + 1)
        case 0x42:
            let count = try checkedCount(readVarint())
            try skip(count)
            value = .undefined
            references.append(value)
        case 0x70:
            _ = try readVarint()
            value = .undefined
            references.append(value)
        case 0x72:
            value = try readError(depth: depth + 1)
        default:
            throw ClaudeHomeV8DecodeError.unsupportedTag(tag)
        }

        if let next = try? peekTag(), next == 0x56 {
            _ = try readTag()
            _ = try readVarint()
            _ = try readVarint()
            _ = try readVarint()
            if version >= 14 {
                _ = try readVarint()
            }
            references.append(value)
        }
        return value
    }

    private mutating func readObject(depth: Int) throws -> ClaudeHomeV8Value {
        let object = ClaudeHomeV8Object()
        let value = ClaudeHomeV8Value.object(object)
        references.append(value)
        while try peekTag() != 0x7b {
            let key = try propertyKey(readValue(depth: depth))
            object.properties[key] = try readValue(depth: depth)
            guard object.properties.count <= Self.maximumContainerEntries else {
                throw ClaudeHomeV8DecodeError.sizeLimit
            }
        }
        _ = try readTag()
        _ = try readVarint()
        return value
    }

    private mutating func readDenseArray(depth: Int) throws -> ClaudeHomeV8Value {
        let count = try checkedCount(readVarint())
        let array = ClaudeHomeV8Array(count: count)
        let value = ClaudeHomeV8Value.array(array)
        references.append(value)
        for index in 0..<count {
            array.values[index] = try readValue(depth: depth)
        }
        try readArrayProperties(array, endTag: 0x24, depth: depth)
        _ = try readVarint()
        _ = try readVarint()
        return value
    }

    private mutating func readSparseArray(depth: Int) throws -> ClaudeHomeV8Value {
        let count = try checkedCount(readVarint())
        let array = ClaudeHomeV8Array(count: count)
        let value = ClaudeHomeV8Value.array(array)
        references.append(value)
        try readArrayProperties(array, endTag: 0x40, depth: depth)
        _ = try readVarint()
        _ = try readVarint()
        return value
    }

    private mutating func readArrayProperties(
        _ array: ClaudeHomeV8Array,
        endTag: UInt8,
        depth: Int
    ) throws {
        while try peekTag() != endTag {
            let keyValue = try readValue(depth: depth)
            let nested = try readValue(depth: depth)
            if case .int(let index) = keyValue,
               index >= 0,
               index < Int64(array.values.count) {
                array.values[Int(index)] = nested
            } else {
                array.properties[try propertyKey(keyValue)] = nested
            }
            guard array.properties.count <= Self.maximumContainerEntries else {
                throw ClaudeHomeV8DecodeError.sizeLimit
            }
        }
        _ = try readTag()
    }

    private mutating func readMap(depth: Int) throws -> ClaudeHomeV8Value {
        let array = ClaudeHomeV8Array(count: 0)
        let value = ClaudeHomeV8Value.array(array)
        references.append(value)
        while try peekTag() != 0x3a {
            array.values.append(try readValue(depth: depth))
            array.values.append(try readValue(depth: depth))
            guard array.values.count <= Self.maximumContainerEntries else {
                throw ClaudeHomeV8DecodeError.sizeLimit
            }
        }
        _ = try readTag()
        _ = try readVarint()
        return value
    }

    private mutating func readSet(depth: Int) throws -> ClaudeHomeV8Value {
        let array = ClaudeHomeV8Array(count: 0)
        let value = ClaudeHomeV8Value.array(array)
        references.append(value)
        while try peekTag() != 0x2c {
            array.values.append(try readValue(depth: depth))
            guard array.values.count <= Self.maximumContainerEntries else {
                throw ClaudeHomeV8DecodeError.sizeLimit
            }
        }
        _ = try readTag()
        _ = try readVarint()
        return value
    }

    private mutating func readError(depth: Int) throws -> ClaudeHomeV8Value {
        let object = ClaudeHomeV8Object()
        let value = ClaudeHomeV8Value.object(object)
        var isRegistered = false
        while true {
            let tag = UInt8(try readVarint())
            switch tag {
            case 0x45:
                object.properties["name"] = .string("EvalError")
            case 0x52:
                object.properties["name"] = .string("RangeError")
            case 0x46:
                object.properties["name"] = .string("ReferenceError")
            case 0x53:
                object.properties["name"] = .string("SyntaxError")
            case 0x54:
                object.properties["name"] = .string("TypeError")
            case 0x55:
                object.properties["name"] = .string("URIError")
            case 0x6d:
                object.properties["message"] = try readValue(depth: depth)
            case 0x73:
                object.properties["stack"] = try readValue(depth: depth)
            case 0x63:
                if !isRegistered {
                    references.append(value)
                    isRegistered = true
                }
                object.properties["cause"] = try readValue(depth: depth)
            case 0x2e:
                if !isRegistered {
                    references.append(value)
                }
                return value
            default:
                throw ClaudeHomeV8DecodeError.invalidFormat
            }
        }
    }

    private func propertyKey(_ value: ClaudeHomeV8Value) throws -> String {
        switch value {
        case .string(let key):
            return key
        case .int(let key):
            return String(key)
        case .double(let key):
            return String(key)
        default:
            throw ClaudeHomeV8DecodeError.invalidFormat
        }
    }

    private mutating func readTag() throws -> UInt8 {
        while true {
            let byte = try readByte()
            if byte == 0 { continue }
            if byte == 0x3f {
                _ = try readVarint()
                continue
            }
            return byte
        }
    }

    private mutating func peekTag() throws -> UInt8 {
        let saved = offset
        defer { offset = saved }
        return try readTag()
    }

    private mutating func readByte() throws -> UInt8 {
        guard bytes.indices.contains(offset) else {
            throw ClaudeHomeV8DecodeError.truncated
        }
        defer { offset += 1 }
        return bytes[offset]
    }

    private mutating func readVarint() throws -> UInt64 {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        for _ in 0..<10 {
            let byte = try readByte()
            value |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        throw ClaudeHomeV8DecodeError.invalidFormat
    }

    private mutating func readZigZag() throws -> Int64 {
        let raw = try readVarint()
        return Int64(raw >> 1) ^ -Int64(raw & 1)
    }

    private mutating func readBigInt() throws -> ClaudeHomeV8Value {
        let bitField = try readVarint()
        let byteCount = try checkedCount(bitField >> 1)
        try skip(byteCount)
        return .undefined
    }

    private mutating func readDouble() throws -> Double {
        var bits: UInt64 = 0
        for shift in stride(from: 0, to: 64, by: 8) {
            bits |= UInt64(try readByte()) << UInt64(shift)
        }
        return Double(bitPattern: bits)
    }

    private mutating func readString(encoding: String.Encoding) throws -> String {
        let count = try checkedCount(readVarint())
        guard offset + count <= bytes.count else {
            throw ClaudeHomeV8DecodeError.truncated
        }
        let data = Data(bytes[offset..<(offset + count)])
        offset += count
        guard let value = String(data: data, encoding: encoding) else {
            throw ClaudeHomeV8DecodeError.invalidFormat
        }
        return value
    }

    private mutating func skip(_ count: Int) throws {
        guard count >= 0, offset + count <= bytes.count else {
            throw ClaudeHomeV8DecodeError.truncated
        }
        offset += count
    }

    private func checkedCount(_ value: UInt64) throws -> Int {
        guard value <= UInt64(Self.maximumExpandedBytes),
              value <= UInt64(Int.max) else {
            throw ClaudeHomeV8DecodeError.sizeLimit
        }
        return Int(value)
    }

    private static func decompressSnappy(_ compressed: [UInt8]) throws -> [UInt8] {
        var inputOffset = 0
        let expected = try readSnappyVarint(compressed, offset: &inputOffset)
        guard expected <= maximumExpandedBytes else {
            throw ClaudeHomeV8DecodeError.sizeLimit
        }
        var output: [UInt8] = []
        output.reserveCapacity(expected)

        while output.count < expected {
            guard compressed.indices.contains(inputOffset) else {
                throw ClaudeHomeV8DecodeError.truncated
            }
            let tag = compressed[inputOffset]
            inputOffset += 1
            let kind = tag & 0x03
            if kind == 0 {
                var length = Int(tag >> 2) + 1
                if length > 60 {
                    let extraBytes = length - 60
                    guard extraBytes <= 4, inputOffset + extraBytes <= compressed.count else {
                        throw ClaudeHomeV8DecodeError.invalidFormat
                    }
                    var encodedLength = 0
                    for byteIndex in 0..<extraBytes {
                        encodedLength |= Int(compressed[inputOffset + byteIndex]) << (byteIndex * 8)
                    }
                    inputOffset += extraBytes
                    length = encodedLength + 1
                }
                guard inputOffset + length <= compressed.count,
                      output.count + length <= expected else {
                    throw ClaudeHomeV8DecodeError.truncated
                }
                output.append(contentsOf: compressed[inputOffset..<(inputOffset + length)])
                inputOffset += length
                continue
            }

            let length: Int
            let copyOffset: Int
            switch kind {
            case 1:
                guard compressed.indices.contains(inputOffset) else {
                    throw ClaudeHomeV8DecodeError.truncated
                }
                length = Int((tag >> 2) & 0x07) + 4
                copyOffset = Int(tag >> 5) << 8 | Int(compressed[inputOffset])
                inputOffset += 1
            case 2:
                guard inputOffset + 2 <= compressed.count else {
                    throw ClaudeHomeV8DecodeError.truncated
                }
                length = Int(tag >> 2) + 1
                copyOffset = Int(compressed[inputOffset])
                    | Int(compressed[inputOffset + 1]) << 8
                inputOffset += 2
            default:
                guard inputOffset + 4 <= compressed.count else {
                    throw ClaudeHomeV8DecodeError.truncated
                }
                length = Int(tag >> 2) + 1
                copyOffset = Int(compressed[inputOffset])
                    | Int(compressed[inputOffset + 1]) << 8
                    | Int(compressed[inputOffset + 2]) << 16
                    | Int(compressed[inputOffset + 3]) << 24
                inputOffset += 4
            }
            guard copyOffset > 0,
                  copyOffset <= output.count,
                  output.count + length <= expected else {
                throw ClaudeHomeV8DecodeError.invalidFormat
            }
            for _ in 0..<length {
                output.append(output[output.count - copyOffset])
            }
        }
        guard output.count == expected else {
            throw ClaudeHomeV8DecodeError.truncated
        }
        return output
    }

    private static func readSnappyVarint(_ bytes: [UInt8], offset: inout Int) throws -> Int {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        for _ in 0..<10 {
            guard bytes.indices.contains(offset) else {
                throw ClaudeHomeV8DecodeError.truncated
            }
            let byte = bytes[offset]
            offset += 1
            value |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 {
                guard value <= UInt64(Int.max) else {
                    throw ClaudeHomeV8DecodeError.sizeLimit
                }
                return Int(value)
            }
            shift += 7
        }
        throw ClaudeHomeV8DecodeError.invalidFormat
    }
}
