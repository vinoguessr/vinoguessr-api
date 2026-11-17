// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "App",
  platforms: [.macOS(.v27)],
  products: [
    .executable(
      name: "App",
      targets: ["App"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/brokenhandsio/swift-cbor.git", exact: "0.3.0"),
    .package(url: "https://github.com/apple/swift-crypto.git", from: "5.1.1"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.28.1"),
    .package(url: "https://github.com/hummingbird-project/hummingbird-auth.git", from: "2.5.0"),
    .package(
      url: "https://github.com/hummingbird-project/swift-openapi-hummingbird.git", from: "2.1.0"),
    .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.14.4"),
    .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.9.0"),
    .package(url: "https://github.com/zunda-pixel/cloudflare-swift.git", from: "0.8.3"),
    .package(
      url: "https://github.com/zunda-pixel/http-client.git",
      from: "0.5.0",
      traits: ["AsyncHTTPClient"]
    ),
    .package(url: "https://github.com/valkey-io/valkey-swift.git", from: "1.6.0"),
    .package(url: "https://github.com/swift-otel/swift-otel.git", from: "1.6.0"),
    .package(
      url: "https://github.com/swift-compositions/swift-postgresql.git",
      revision: "837a5c0d43b495372c17de08d5f187f6819601b0",
      traits: ["PostgresNIO"]
    ),
    .package(url: "https://github.com/swift-compositions/swift-sql.git", branch: "main"),
    .package(url: "https://github.com/zunda-pixel/swift-currency.git", from: "0.0.1"),
    .package(
      url: "https://github.com/brokenhandsio/swift-webauthn.git",
      from: "1.0.0-beta.3"
    ),
    .package(url: "https://github.com/zunda-pixel/UUIDV7.git", branch: "replace-to-swift-testing"),
  ],
  targets: [
    .executableTarget(
      name: "App",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "CBOR", package: "swift-cbor"),
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "HummingbirdAuth", package: "hummingbird-auth"),
        .product(name: "Valkey", package: "valkey-swift"),
        .product(name: "WebAuthn", package: "swift-webauthn"),
        .product(name: "OpenAPIHummingbird", package: "swift-openapi-hummingbird"),
        .product(name: "JWTKit", package: "jwt-kit"),
        .product(name: "PostgreSQL", package: "swift-postgresql"),
        .product(name: "SQL Macros", package: "swift-sql"),
        .product(name: "SQL Foundation Integration", package: "swift-sql"),
        .product(name: "Currency", package: "swift-currency"),
        .product(name: "CloudflareEmailService", package: "cloudflare-swift"),
        .product(name: "CloudflareImages", package: "cloudflare-swift"),
        .product(name: "HTTPClient", package: "http-client"),
        .product(name: "UUIDV7", package: "UUIDV7"),
        .product(name: "OTel", package: "swift-otel"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("ImmutableWeakCaptures"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .strictMemorySafety(),
        .treatAllWarnings(as: .error),
      ],
      plugins: [
        .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
      ],
    ),
    .testTarget(
      name: "AppTests",
      dependencies: [
        .target(name: "App"),
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "CBOR", package: "swift-cbor"),
        .product(name: "HummingbirdTesting", package: "hummingbird"),
        .product(name: "OTel", package: "swift-otel"),
      ]
    ),
  ]
)
