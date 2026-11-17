import Configuration
import Foundation
import ISO_9075_Foundation
import Logging
import PostgreSQL
import SQL
import SQL_Foundation_Integration
import Testing

@testable import App

struct PostgreSQLQueryTests {
  @Test
  func foundationValuesUsePostgresBindings() async throws {
    let id = UUID()
    let date = Date(timeIntervalSince1970: 1_700_000_000.125)
    let data = Data([0, 127, 128, 255])
    let fragment: ISO_9075.Fragment =
      "SELECT \(id, as: UUID.self), \(date, as: Date.self), \(data, as: Data.self)"
    let rendering = try PostgreSQL().render(fragment)
    #expect(rendering.sql == "SELECT $1, $2, $3")
    #expect(rendering.values == [id.queryBinding, date.queryBinding, data.queryBinding])
    let database = try await makeDatabase(
      arguments: TestArguments(),
      config: ConfigReader(providers: [EnvironmentVariablesProvider()]),
      logger: Logger(label: "PostgreSQLQueryTests")
    )
    let values = try await database.read { connection throws(ISO_9075.Error) in
      try connection.fetchAll(rendering) { row throws(ISO_9075.Error) in
        [try row.value(at: 0), try row.value(at: 1), try row.value(at: 2)]
      }
    }
    await database.close()
    #expect(values == [rendering.values])
  }

  @Test
  func concurrentReadsKeepTheirBindings() async throws {
    let database = try await makeDatabase(
      arguments: TestArguments(),
      config: ConfigReader(providers: [EnvironmentVariablesProvider()]),
      logger: Logger(label: "PostgreSQLQueryTests")
    )
    let results = try await withThrowingTaskGroup(of: Int64.self) { group in
      for value in 0..<32 {
        group.addTask {
          let fragment: ISO_9075.Fragment = "SELECT \(Int64(value), as: Int64.self)"
          return try await database.read { connection throws(ISO_9075.Error) in
            let values = try connection.fetchAll(fragment) { row throws(ISO_9075.Error) in
              try row.value(at: 0)
            }
            guard case .int(let result)? = values.first else {
              throw .decoding("Expected one integer binding")
            }
            return result
          }
        }
      }
      var results: [Int64] = []
      for try await result in group { results.append(result) }
      return results
    }
    await database.close()
    #expect(results.sorted() == Array(0..<32).map(Int64.init))
  }

  @Test
  func untrustedTextRemainsABoundParameter() throws {
    let input = "x'; DROP TABLE users; --"
    let fragment: ISO_9075.Fragment = "SELECT \(input, as: String.self)"
    let rendering = try PostgreSQL().render(fragment)
    #expect(rendering.sql == "SELECT $1")
    #expect(rendering.values == [.text(input)])
  }
}
