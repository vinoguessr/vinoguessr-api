import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import App

struct PasskeyRequestMiddlewareTests {
  private let request = HTTPRequest(
    method: .post, scheme: "http", authority: "localhost", path: "/passkey")
  private let metadata = ServerRequestMetadata(pathParameters: [:])

  @Test(arguments: ["addPasskey", "createTokenFromPasskey"])
  func rejectsDuplicateOuterJSONProperties(operation: String) async throws {
    for json in [#"{"id":"same","id":"same"}"#, #"{"id":"same","\u0069d":"same"}"#] {
      let (response, _) = try await PasskeyRequestMiddleware().intercept(
        request,
        body: HTTPBody(json), metadata: metadata, operationID: operation
      ) { _, _, _ in (HTTPResponse(status: .ok), nil) }
      #expect(response.status == .badRequest)
    }
  }

  @Test(arguments: ["addPasskey", "createTokenFromPasskey"])
  func rejectsUnknownLengthChunkedBodyBeyondLimit(operation: String) async throws {
    let chunks = AsyncStream<ArraySlice<UInt8>> { continuation in
      continuation.yield(Array(repeating: UInt8(0x20), count: 262_143)[...])
      continuation.yield([0x20, 0x20])
      continuation.finish()
    }
    var request = request
    request.headerFields[.contentLength] = "1"
    let (response, body) = try await PasskeyRequestMiddleware().intercept(
      request,
      body: HTTPBody(chunks, length: .unknown), metadata: metadata, operationID: operation
    ) { _, _, _ in
      Issue.record("Oversized passkey body reached the generated handler")
      return (HTTPResponse(status: .ok), nil)
    }
    #expect(response.status == .contentTooLarge)
    #expect(
      try await String(collecting: #require(body), upTo: 1024) == #"{"error":"payload_too_large"}"#)
  }

  @Test func preservesBodyAtLimitAndLeavesOtherOperationsUnrestricted() async throws {
    let expected = Array("{}".utf8) + Array(repeating: UInt8(0x20), count: 262_142)
    let (response, body) = try await PasskeyRequestMiddleware().intercept(
      request,
      body: HTTPBody(expected), metadata: metadata, operationID: "addPasskey"
    ) { _, body, _ in (HTTPResponse(status: .ok), body) }
    #expect(response.status == .ok)
    #expect(try await Array(collecting: #require(body), upTo: 262_144) == expected)
    let (unrestricted, _) = try await PasskeyRequestMiddleware().intercept(
      request,
      body: HTTPBody(expected + [0x20]), metadata: metadata, operationID: "createUser"
    ) { _, _, _ in (HTTPResponse(status: .accepted), nil) }
    #expect(unrestricted.status == .accepted)
  }

  @Test func mapsOnlyRequestDecodingFailuresAndPropagatesHandlerErrors() async throws {
    let decoding = DecodingError.keyNotFound(
      Key(), .init(codingPath: [], debugDescription: "Synthetic test"))
    let request = request
    let metadata = metadata
    let (response, body) = try await PasskeyRequestMiddleware().intercept(
      request,
      body: nil, metadata: metadata, operationID: "createTokenFromPasskey"
    ) { _, _, _ in
      throw ServerError(
        operationID: "createTokenFromPasskey", request: request, requestBody: nil,
        requestMetadata: metadata, causeDescription: "Synthetic test", underlyingError: decoding,
        httpStatus: .badRequest, httpHeaderFields: [:], httpBody: nil)
    }
    #expect(response.status == .badRequest)
    #expect(
      try await String(collecting: #require(body), upTo: 1024) == #"{"error":"invalid_request"}"#)
    for (input, status) in [
      (String?.some("Decoded input"), HTTPResponse.Status.badRequest),
      (nil, .internalServerError),
    ] {
      await #expect(throws: ServerError.self) {
        try await PasskeyRequestMiddleware().intercept(
          request, body: nil, metadata: metadata,
          operationID: "createTokenFromPasskey"
        ) { _, _, _ in
          throw ServerError(
            operationID: "createTokenFromPasskey", request: request, requestBody: nil,
            requestMetadata: metadata, operationInput: input, causeDescription: "Synthetic test",
            underlyingError: decoding, httpStatus: status, httpHeaderFields: [:], httpBody: nil)
        }
      }
    }
  }

  @Test func propagatesRequestStreamFailure() async {
    let chunks = AsyncThrowingStream<ArraySlice<UInt8>, any Error> { continuation in
      continuation.finish(throwing: StreamFailure.failed)
    }
    await #expect(throws: StreamFailure.failed) {
      try await PasskeyRequestMiddleware().intercept(
        request, body: HTTPBody(chunks, length: .unknown),
        metadata: metadata, operationID: "addPasskey"
      ) { _, _, _ in (HTTPResponse(status: .ok), nil) }
    }
  }

  private enum StreamFailure: Error { case failed }
  private struct Key: CodingKey {
    var stringValue: String { "userHandle" }
    var intValue: Int? { nil }
    init() {}
    init?(stringValue: String) { return nil }
    init?(intValue: Int) { return nil }
  }
}
