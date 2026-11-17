import CBOR
import Foundation
import WebAuthn

enum PasskeyInputError: Error {
  case invalidCredential
}

enum PasskeyInputValidation {
  static func registration(_ credential: RegistrationCredential) throws {
    try identity(credential.id, rawID: credential.rawID)
    try client(credential.attestationResponse.clientDataJSON)
    let object = try map(credential.attestationResponse.attestationObject)
    guard case .byteString(let auth)? = object[.textString("authData")], auth.count >= 55 else {
      throw PasskeyInputError.invalidCredential
    }
    try flags(auth[32], registration: true)
    let length = Int(auth[53]) * 256 + Int(auth[54])
    let end = 55 + length
    guard (1...1023).contains(length), end < auth.count,
      Array(auth[55..<end]) == credential.rawID
    else { throw PasskeyInputError.invalidCredential }
    let (key, consumed) = try CBOR.decodeFirst(auth[end...], options: options)
    guard case .map = key else { throw PasskeyInputError.invalidCredential }
    try extensions(Array(auth[(end + consumed)...]), flags: auth[32])
  }

  static func authentication(_ credential: AuthenticationCredential, publicKey: [UInt8]) throws {
    try identity(credential.id, rawID: credential.rawID)
    try client(credential.response.clientDataJSON)
    _ = try map(publicKey)
    let auth = credential.response.authenticatorData
    guard (37...65_536).contains(auth.count) else { throw PasskeyInputError.invalidCredential }
    try flags(auth[32], registration: false)
    try extensions(Array(auth[37...]), flags: auth[32])
  }

  private static let options = CBOROptions(maximumDepth: 16, rejectDuplicateMapKeys: true)

  private static func map(_ bytes: [UInt8]) throws -> [CBOR: CBOR] {
    guard !bytes.isEmpty, bytes.count <= 65_536,
      case .map(let object) = try CBOR.decode(bytes, options: options)
    else { throw PasskeyInputError.invalidCredential }
    return object
  }

  private static func identity(_ id: URLEncodedBase64, rawID: [UInt8]) throws {
    guard (1...1023).contains(rawID.count), id == rawID.base64URLEncodedString() else {
      throw PasskeyInputError.invalidCredential
    }
  }

  private static func flags(_ value: UInt8, registration: Bool) throws {
    guard (value & 0x40 != 0) == registration,
      value & 0x10 == 0 || value & 0x08 != 0
    else { throw PasskeyInputError.invalidCredential }
  }

  private static func extensions(_ bytes: [UInt8], flags: UInt8) throws {
    if flags & 0x80 != 0 {
      _ = try map(bytes)
    } else if !bytes.isEmpty {
      throw PasskeyInputError.invalidCredential
    }
  }

  private static func client(_ bytes: [UInt8]) throws {
    guard bytes.count <= 16_384 else { throw PasskeyInputError.invalidCredential }
    let data = Data(bytes)
    try rejectDuplicatePasskeyJSONProperties(data)
    let client = try JSONDecoder().decode(ClientContext.self, from: data)
    guard client.crossOrigin != true, !client.hasTopOrigin else {
      throw PasskeyInputError.invalidCredential
    }
  }

  private struct ClientContext: Decodable {
    let crossOrigin: Bool?
    let hasTopOrigin: Bool
    enum CodingKeys: String, CodingKey { case crossOrigin, topOrigin }
    init(from decoder: any Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      hasTopOrigin = values.contains(.topOrigin)
      crossOrigin =
        values.contains(.crossOrigin) ? try values.decode(Bool.self, forKey: .crossOrigin) : nil
    }
  }
}
