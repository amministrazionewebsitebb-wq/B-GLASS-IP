import Foundation

/// A very small test harness (XCTest is not available with the command line tools only).
final class Harness {
    private(set) var passed = 0
    private(set) var failed = 0
    private var current = ""

    func suite(_ name: String, _ body: () throws -> Void) {
        current = name
        do { try body() } catch {
            failed += 1
            print("  FAIL [\(name)] threw \(error)")
        }
    }

    func suite(_ name: String, _ body: () async throws -> Void) async {
        current = name
        do { try await body() } catch {
            failed += 1
            print("  FAIL [\(name)] threw \(error)")
        }
    }

    func check(_ cond: @autoclosure () -> Bool, _ msg: String = "", file: StaticString = #file, line: UInt = #line) {
        if cond() { passed += 1 } else {
            failed += 1
            print("  FAIL [\(current)] \(msg) (\(URL(fileURLWithPath: "\(file)").lastPathComponent):\(line))")
        }
    }

    func equal<T: Equatable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ msg: String = "", file: StaticString = #file, line: UInt = #line) {
        let x = a(), y = b()
        if x == y { passed += 1 } else {
            failed += 1
            print("  FAIL [\(current)] \(msg) expected \(y), got \(x) (\(URL(fileURLWithPath: "\(file)").lastPathComponent):\(line))")
        }
    }

    func isNil<T>(_ a: @autoclosure () -> T?, _ msg: String = "", file: StaticString = #file, line: UInt = #line) {
        if a() == nil { passed += 1 } else {
            failed += 1
            print("  FAIL [\(current)] \(msg) expected nil (\(URL(fileURLWithPath: "\(file)").lastPathComponent):\(line))")
        }
    }

    func summary() -> Int32 {
        print("\n\(passed) checks passed, \(failed) failed")
        return failed == 0 ? 0 : 1
    }
}
