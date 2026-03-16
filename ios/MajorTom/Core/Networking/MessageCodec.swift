import Foundation

enum MessageCodec {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }()

    static func encode<T: Encodable>(_ message: T) throws -> Data {
        try encoder.encode(message)
    }

    static func encodeToString<T: Encodable>(_ message: T) throws -> String {
        let data = try encode(message)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CodecError.encodingFailed
        }
        return string
    }

    static func decodeType(from data: Data) -> MessageType? {
        guard let envelope = try? decoder.decode(MessageEnvelope.self, from: data) else {
            return nil
        }
        return MessageType(rawValue: envelope.type)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}

enum CodecError: Error {
    case encodingFailed
    case unknownMessageType(String)
}
