import CBOR
import Crypto
import Foundation
import Testing
import WebAuthn

@testable import App

private let signedChallenge = Array(repeating: UInt8(0x51), count: 32)
private let signedOrigin = "http://localhost:8080"

struct SyntheticPasskey {
  private let key = P256.Signing.PrivateKey()
  let id = Array(UUID().uuidString.utf8)

  var publicKey: [UInt8] {
    let point = Array(key.publicKey.x963Representation)
    return CBOR.map([
      .unsignedInt(1): .unsignedInt(2), .unsignedInt(3): .negativeInt(6),
      .negativeInt(0): .unsignedInt(1),
      .negativeInt(1): .byteString(Array(point[1..<33])),
      .negativeInt(2): .byteString(Array(point[33..<65])),
    ]).encode()
  }

  func client(
    type: String, challenge: [UInt8] = signedChallenge, origin: String = signedOrigin,
    extra: [String: Any] = [:]
  ) throws -> Data {
    var value: [String: Any] = ["type": type, "challenge": encode(challenge), "origin": origin]
    value.merge(extra) { _, new in new }
    return try JSONSerialization.data(withJSONObject: value, options: .sortedKeys)
  }

  func auth(flags: UInt8, counter: UInt32 = 0, rp: String = "localhost") -> [UInt8] {
    Array(SHA256.hash(data: Data(rp.utf8))) + [
      flags,
      UInt8(truncatingIfNeeded: counter >> 24), UInt8(truncatingIfNeeded: counter >> 16),
      UInt8(truncatingIfNeeded: counter >> 8), UInt8(truncatingIfNeeded: counter),
    ]
  }

  func registration(
    flags: UInt8 = 0x45, rp: String = "localhost", clientData: Data? = nil,
    envelopeID: [UInt8]? = nil, rawID: [UInt8]? = nil, cose: [UInt8]? = nil,
    duplicateFormat: Bool = false, suffix: [UInt8] = []
  ) throws -> RegistrationCredential {
    let client = try clientData ?? self.client(type: "webauthn.create")
    let auth =
      auth(flags: flags, rp: rp) + Array(repeating: 0, count: 16)
      + [0, UInt8(id.count)] + id + (cose ?? publicKey)
    let attestation: [UInt8]
    if duplicateFormat {
      attestation =
        [0xa4] + CBOR.textString("fmt").encode() + CBOR.textString("none").encode()
        + CBOR.textString("fmt").encode() + CBOR.textString("none").encode()
        + CBOR.textString("authData").encode() + CBOR.byteString(auth).encode()
        + CBOR.textString("attStmt").encode() + CBOR.map([:]).encode()
    } else {
      attestation = CBOR.map([
        .textString("fmt"): .textString("none"),
        .textString("authData"): .byteString(auth), .textString("attStmt"): .map([:]),
      ]).encode()
    }
    let json = try JSONSerialization.data(withJSONObject: [
      "id": encode(envelopeID ?? id),
      "rawId": encode(rawID ?? id), "type": "public-key",
      "response": [
        "clientDataJSON": encode(client), "attestationObject": encode(attestation + suffix),
      ],
    ])
    return try JSONDecoder().decode(RegistrationCredential.self, from: json)
  }

  func assertion(
    flags: UInt8 = 0x05, rp: String = "localhost", counter: UInt32 = 1,
    clientData: Data? = nil, rawID: [UInt8]? = nil, tamper: Bool = false,
    authSuffix: [UInt8] = [], userHandle: Data? = nil, signatureOverride: [UInt8]? = nil
  ) throws -> AuthenticationCredential {
    let client = try clientData ?? self.client(type: "webauthn.get")
    let auth = auth(flags: flags, counter: counter, rp: rp) + authSuffix
    var signature =
      try signatureOverride
      ?? Array(key.signature(for: auth + Array(SHA256.hash(data: client))).derRepresentation)
    if tamper { signature[signature.count - 1] ^= 1 }
    var response = [
      "clientDataJSON": encode(client), "authenticatorData": encode(auth),
      "signature": encode(signature),
    ]
    if let userHandle { response["userHandle"] = encode(userHandle) }
    let json = try JSONSerialization.data(withJSONObject: [
      "id": encode(id),
      "rawId": encode(rawID ?? id), "type": "public-key", "response": response,
    ])
    return try JSONDecoder().decode(AuthenticationCredential.self, from: json)
  }

  private func encode(_ data: some Sequence<UInt8>) -> String {
    Data(data).base64EncodedString().replacing("+", with: "-").replacing("/", with: "_").replacing(
      "=", with: "")
  }
}

struct LiveWebAuthnTests {
  private var verifier: LiveWebAuthn {
    .init(
      manager: WebAuthnManager(
        configuration: .init(
          relyingPartyID: "localhost",
          relyingPartyName: "Synthetic tests", relyingPartyOrigin: signedOrigin)))
  }

  private func register(_ credential: RegistrationCredential, requireUV: Bool = false) async throws
    -> Credential
  {
    try await verifier.finishRegistration(
      challenge: signedChallenge, credentialCreationData: credential,
      requireUserVerification: requireUV, supportedPublicKeyAlgorithms: .supported,
      pemRootCertificatesByFormat: [:], confirmCredentialIDNotRegisteredYet: { _ in true })
  }

  private func authenticate(
    _ credential: AuthenticationCredential, key: [UInt8], counter: UInt32 = 0,
    requireUV: Bool = false
  ) throws -> VerifiedAuthentication {
    try verifier.finishAuthentication(
      credential: credential, expectedChallenge: signedChallenge,
      credentialPublicKey: key, credentialCurrentSignCount: counter,
      requireUserVerification: requireUV)
  }

  @Test func registersGeneratedKeyAndVerifiesItsSignedAssertion() async throws {
    let passkey = SyntheticPasskey()
    let credential = try await register(passkey.registration())
    #expect(credential.publicKey == passkey.publicKey)
    #expect(credential.signCount == 0)
    let result = try authenticate(passkey.assertion(), key: credential.publicKey)
    #expect(result.credentialID == passkey.id.base64URLEncodedString())
    #expect(result.newSignCount == 1)
  }

  @Test func preservesOptionalUserVerificationAndSignedUnknownClientFields() async throws {
    let passkey = SyntheticPasskey()
    let registration = try await register(passkey.registration(flags: 0x41))
    let client = try passkey.client(type: "webauthn.get", extra: ["future": ["nested": true]])
    _ = try authenticate(
      passkey.assertion(flags: 0x01, clientData: client), key: registration.publicKey)
    let unverified = try passkey.assertion(flags: 0x01)
    #expect(throws: (any Error).self) {
      try authenticate(unverified, key: registration.publicKey, requireUV: true)
    }
  }

  @Test func acceptsZeroCountersValidBackupFlagsAndAuthenticatorExtensions() async throws {
    let passkey = SyntheticPasskey()
    let extensionBytes = CBOR.map([.textString("future"): .bool(true)]).encode()
    let registered = try await register(
      passkey.registration(flags: 0xdd, cose: passkey.publicKey + extensionBytes))
    #expect(registered.backupEligible)
    #expect(registered.isBackedUp)
    let authenticated = try authenticate(
      passkey.assertion(flags: 0x9d, counter: 0, authSuffix: extensionBytes),
      key: registered.publicKey)
    #expect(authenticated.newSignCount == 0)
    #expect(authenticated.credentialBackedUp)
  }

  @Test func preservesP384AlgorithmSupport() async throws {
    let passkey = SyntheticPasskey()
    let key = P384.Signing.PrivateKey()
    let point = Array(key.publicKey.x963Representation)
    let cose = CBOR.map([
      .unsignedInt(1): .unsignedInt(2), .unsignedInt(3): .negativeInt(34),
      .negativeInt(0): .unsignedInt(2), .negativeInt(1): .byteString(Array(point[1..<49])),
      .negativeInt(2): .byteString(Array(point[49..<97])),
    ]).encode()
    let registered = try await register(passkey.registration(cose: cose))
    let client = try passkey.client(type: "webauthn.get")
    let signed = passkey.auth(flags: 0x05, counter: 1) + Array(SHA256.hash(data: client))
    let signature = Array(try key.signature(for: signed).derRepresentation)
    let credential = try passkey.assertion(clientData: client, signatureOverride: signature)
    #expect(try authenticate(credential, key: registered.publicKey).newSignCount == 1)
  }

  @Test func rejectsSignedClientDataBeyondSizeAndDepthLimits() throws {
    let passkey = SyntheticPasskey()
    var nested: Any = true
    for _ in 0..<20 { nested = ["nested": nested] }
    let clients = try [
      passkey.client(
        type: "webauthn.get", extra: ["future": String(repeating: "x", count: 16_385)]),
      passkey.client(type: "webauthn.get", extra: ["future": nested]),
    ]
    for client in clients {
      let signed = try passkey.assertion(clientData: client)
      #expect(throws: PasskeyInputError.invalidCredential) {
        try authenticate(signed, key: passkey.publicKey)
      }
    }
  }

  @Test func rejectsWrongRegistrationChallengeOriginRPAndRequiredUV() async throws {
    let passkey = SyntheticPasskey()
    let cases = try [
      passkey.registration(rp: "other.invalid"),
      passkey.registration(clientData: passkey.client(type: "webauthn.create", challenge: [1])),
      passkey.registration(
        clientData: passkey.client(type: "webauthn.create", origin: "https://other.invalid")),
      passkey.registration(flags: 0x44), passkey.registration(flags: 0x41),
    ]
    for credential in cases {
      await #expect(throws: (any Error).self) { try await register(credential, requireUV: true) }
    }
  }

  @Test func rejectsWrongSignatureKeyChallengeOriginRPAndNonIncreasingCounter() async throws {
    let passkey = SyntheticPasskey()
    let registered = try await register(passkey.registration())
    let cases = try [
      passkey.assertion(tamper: true), passkey.assertion(rp: "other.invalid"),
      passkey.assertion(clientData: passkey.client(type: "webauthn.get", challenge: [1])),
      passkey.assertion(
        clientData: passkey.client(type: "webauthn.get", origin: "https://other.invalid")),
      passkey.assertion(flags: 0x04),
    ]
    for credential in cases {
      #expect(throws: (any Error).self) {
        try authenticate(credential, key: registered.publicKey, counter: 0)
      }
    }
    let signed = try passkey.assertion()
    let otherKey = SyntheticPasskey().publicKey
    #expect(throws: (any Error).self) { try authenticate(signed, key: otherKey) }
    let zero = try passkey.assertion(counter: 0)
    let repeated = try passkey.assertion(counter: 4)
    #expect(throws: (any Error).self) {
      try authenticate(zero, key: registered.publicKey, counter: 1)
    }
    #expect(throws: (any Error).self) {
      try authenticate(repeated, key: registered.publicKey, counter: 4)
    }
  }

  @Test func rejectsRegistrationIdentityMismatchDuplicateMapsAndInconsistentBackupFlags()
    async throws
  {
    let passkey = SyntheticPasskey()
    let duplicateKey =
      [UInt8(0xa6)] + Array(passkey.publicKey.dropFirst())
      + CBOR.unsignedInt(1).encode() + CBOR.unsignedInt(2).encode()
    for credential in try [
      passkey.registration(envelopeID: [1]), passkey.registration(rawID: [1]),
      passkey.registration(envelopeID: [1], rawID: [1]),
      passkey.registration(duplicateFormat: true),
      passkey.registration(cose: duplicateKey), passkey.registration(flags: 0x55),
      passkey.registration(suffix: [0xa0]),
    ] {
      await #expect(throws: (any Error).self) { try await register(credential) }
    }
  }

  @Test func rejectsSignedCrossOriginDuplicateClientFieldsAndMalformedAssertionFlags() async throws
  {
    let passkey = SyntheticPasskey()
    let duplicate = Data(
      ("{\"type\":\"webauthn.get\",\"challenge\":\""
        + signedChallenge.base64URLEncodedString().asString()
        + "\",\"origin\":\"" + signedOrigin
        + "\",\"crossOrigin\":false,\"cross\\u004frigin\":false}").utf8)
    let clientCases = try [
      passkey.client(type: "webauthn.get", extra: ["crossOrigin": true]),
      passkey.client(type: "webauthn.get", extra: ["topOrigin": "https://other.invalid"]),
      duplicate,
    ]
    for client in clientCases {
      let assertion = try passkey.assertion(clientData: client)
      #expect(throws: PasskeyInputError.invalidCredential) {
        try authenticate(assertion, key: passkey.publicKey)
      }
    }
    for credential in try [passkey.assertion(rawID: [1]), passkey.assertion(flags: 0x15)] {
      #expect(throws: (any Error).self) { try authenticate(credential, key: passkey.publicKey) }
    }
    let signed = try passkey.assertion()
    #expect(throws: (any Error).self) { try authenticate(signed, key: passkey.publicKey + [0xa0]) }
    let attested =
      Array(repeating: UInt8(0), count: 16) + [0, UInt8(passkey.id.count)] + passkey.id
      + passkey.publicKey
    let assertionWithAttestedData = try passkey.assertion(flags: 0x45, authSuffix: attested)
    #expect(throws: PasskeyInputError.invalidCredential) {
      try authenticate(assertionWithAttestedData, key: passkey.publicKey)
    }
  }
}

func signedPasskeyRequestBody(_ credential: some Encodable, challenge: String) throws -> Data {
  let data = try JSONEncoder().encode(credential)
  var value = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  value["challenge"] = challenge
  return try JSONSerialization.data(withJSONObject: value)
}
