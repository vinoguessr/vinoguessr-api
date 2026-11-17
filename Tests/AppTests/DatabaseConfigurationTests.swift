import Configuration
import Logging
import PostgreSQL
import Testing

@testable import App

struct DatabaseConfigurationTests {
  @Test(arguments: [EnvironmentLevel.develop, .production])
  func databaseTLSMatchesEnvironment(_ environment: EnvironmentLevel) async throws {
    var arguments = TestArguments()
    arguments.env = environment
    let database = try await makeDatabase(
      arguments: arguments,
      config: configuration,
      logger: Logger(label: "DatabaseConfigurationTests")
    )
    #expect(database.configuration.tls.mode == (environment == .production ? .verified : .disabled))
    await database.close()
  }

  @Test
  func cancellingDatabaseServiceClosesDatabase() async throws {
    let database = try await makeDatabase(
      arguments: TestArguments(),
      config: configuration,
      logger: Logger(label: "DatabaseConfigurationTests")
    )
    let task = Task { try await DatabaseService(database: database).run() }
    task.cancel()
    do {
      try await task.value
    } catch is CancellationError {
    }
    do {
      _ = try await database.read { _ throws(PostgreSQL.Error) in 1 }
      Issue.record("A closed database must reject reads")
    } catch {
      #expect(error.kind == .closed)
    }
  }

  private var configuration: ConfigReader {
    ConfigReader(providers: [
      InMemoryProvider(values: [
        "postgres.hostname": "localhost",
        "postgres.user": "test_user",
        "postgres.db": "test_database",
        "postgres.password": "test_password",
      ])
    ])
  }
}
