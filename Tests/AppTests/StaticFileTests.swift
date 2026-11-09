import Hummingbird
import HummingbirdTesting
import Testing

@testable import App

struct StaticFileTests {
  private static let playgroundPaths = ["/", "/index.html", "/app.js", "/styles.css"]
  private static let documentsPaths = ["/documents/", "/documents/openapi.yml"]

  @Test
  func productionServesDocumentsButNotThePlayground() async throws {
    try await withStaticFiles(env: .production) { client in
      for path in Self.playgroundPaths {
        try await client.execute(uri: path, method: .get) { response in
          #expect(response.status == .notFound, "\(path)")
        }
      }
      for path in Self.documentsPaths {
        try await client.execute(uri: path, method: .get) { response in
          #expect(response.status == .ok, "\(path)")
        }
      }
    }
  }

  @Test
  func localDevelopmentServesThePlaygroundAndDocuments() async throws {
    try await withStaticFiles(env: .develop) { client in
      for path in Self.playgroundPaths + Self.documentsPaths {
        try await client.execute(uri: path, method: .get) { response in
          #expect(response.status == .ok, "\(path)")
        }
      }
      try await client.execute(uri: "/", method: .get) { response in
        #expect(String(buffer: response.body).contains("VinoGuessr Passkey Playground"))
      }
    }
  }

  private func withStaticFiles(
    env: EnvironmentLevel,
    _ test: @Sendable (any TestClientProtocol) async throws -> Void
  ) async throws {
    let router = Router(context: AppRequestContext.self)
    addStaticFileMiddleware(to: router, env: env)
    try await Application(router: router).test(.router, test)
  }
}
