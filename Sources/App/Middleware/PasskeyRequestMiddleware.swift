import Foundation
import HTTPTypes
import OpenAPIRuntime

struct PasskeyRequestMiddleware: ServerMiddleware {
  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    metadata: ServerRequestMetadata,
    operationID: String,
    next:
      @Sendable @concurrent (HTTPRequest, HTTPBody?, ServerRequestMetadata) async throws -> (
        HTTPResponse, HTTPBody?
      )
  ) async throws -> (HTTPResponse, HTTPBody?) {
    guard
      operationID == Operations.AddPasskey.id || operationID == Operations.CreateTokenFromPasskey.id
    else {
      return try await next(request, body, metadata)
    }
    var collected: HTTPBody?
    if let body {
      var bytes = [UInt8]()
      // The generated JSON converter otherwise collects the entire request before
      // the credential validator can inspect decoded CBOR or clientDataJSON.
      for try await chunk in body {
        guard chunk.count <= 262_144 - bytes.count else {
          return (
            HTTPResponse(
              status: .contentTooLarge, headerFields: [.contentType: "application/json"]),
            HTTPBody(#"{"error":"payload_too_large"}"#)
          )
        }
        bytes.append(contentsOf: chunk)
      }
      do {
        try rejectDuplicatePasskeyJSONProperties(Data(bytes), maximumBytes: 262_144)
      } catch {
        return (
          HTTPResponse(status: .badRequest, headerFields: [.contentType: "application/json"]),
          HTTPBody(#"{"error":"invalid_request"}"#)
        )
      }
      collected = HTTPBody(bytes)
    }
    do {
      return try await next(request, collected, metadata)
    } catch let error as ServerError
      where error.operationInput == nil && error.underlyingError is DecodingError
      && error.httpStatus == .badRequest
    {
      return (
        HTTPResponse(status: .badRequest, headerFields: [.contentType: "application/json"]),
        HTTPBody(#"{"error":"invalid_request"}"#)
      )
    }
  }
}
