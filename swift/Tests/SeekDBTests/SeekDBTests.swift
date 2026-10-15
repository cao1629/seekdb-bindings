// Copyright (c) 2025 OceanBase.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Dispatch
import Foundation
import XCTest
@testable import SeekDB

final class SeekDBTests: XCTestCase {
    func testRejectsMalformedInputsBeforeCallingNative() {
        let invalid: [(String, [String])] = [
            ("", []), ("/data\0other", []),
            ("/data", ["key"]), ("/data", ["", "value"]),
            ("/data", ["k\0ey", "value"]), ("/data", ["key", "v\0alue"])
        ]
        for (directory, parameters) in invalid {
            let native = MockNativeAPI()
            XCTAssertThrowsError(try SeekDB.open(directory, parameters: parameters, native: native)) { error in
                guard case SeekDBError.invalidArgument = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
            XCTAssertEqual(native.openCount, 0)
        }
    }

    func testPreservesUnicodeEmptyValuesAndParameterOrder() throws {
        let native = MockNativeAPI()
        let parameters = ["memory_budget", "1G", "custom", "", "custom", "向量🦉"]
        let db = try SeekDB.open("/数据库/🦉", parameters: parameters, native: native)
        XCTAssertEqual(native.openDirectory, "/数据库/🦉")
        XCTAssertEqual(native.openParameters, parameters)
        try db.close()
    }

    func testNativeCStringUsesStandardUTF8AndOwnsItsStorage() {
        let value = "数据库🦉"
        let string = NativeCString(value)
        XCTAssertEqual(String(cString: string.buffer), value)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: string.buffer, count: value.utf8.count + 1)),
                       value.utf8.map { CChar(bitPattern: $0) } + [0])
    }

    #if os(macOS) || os(Linux)
    func testRealNativeBridgeRejectsReservedParameterWithoutStartingServer() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("seekdb-swift-数据库🦉-\(UUID().uuidString)").path
        // Native validation scans the complete NUL-terminated pointer array
        // before executable discovery or directory creation. Earlier Unicode
        // values also remain alive for this actual C call.
        XCTAssertThrowsError(try SeekDB.open(directory, parameters: [
            "custom", "向量🦉", "memory_budget", "1G", "mysql_port", "2881"
        ])) { error in
            guard let nativeError = error as? SeekDBError,
                  case .native(operation: .open, code: -2, message: let message) = nativeError else {
                return XCTFail("Unexpected error from the real native bridge: \(error)")
            }
            XCTAssertTrue(message.contains("mysql_port is not supported"), message)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory))
    }
    #endif

    #if os(iOS)
    func testInProcessEngineServesMySQLUntilItsOnlyClose() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("seekdb-swift-\(UUID().uuidString)").path
        let db = try SeekDB.open(directory)
        let options = try db.connectionOptions()
        XCTAssertEqual(options.transport, "unix_socket")
        XCTAssertEqual(options.port, 0)
        XCTAssertNil(options.host)
        XCTAssertNil(options.named_pipe)
        XCTAssertEqual(options.user, "root")
        XCTAssertEqual(try mysqlProtocolVersion(at: XCTUnwrap(options.unix_socket)), 10)
        try db.close()
        XCTAssertThrowsError(try SeekDB.open(directory)) { error in
            guard case SeekDBError.native(operation: .open, code: -1, message: let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("start a new process"), message)
        }
    }
    #endif

    func testOpenFailurePreservesNativeCodeAndMessage() {
        let native = MockNativeAPI(openCode: -17)
        native.openError = "启动失败🦉"
        XCTAssertThrowsError(try SeekDB.open("/data", native: native)) { error in
            XCTAssertEqual(error as? SeekDBError,
                           .native(operation: .open, code: -17, message: "启动失败🦉"))
        }
        XCTAssertEqual(native.closeCount, 0)
    }

    func testOpenRejectsSuccessWithoutHandle() {
        let native = MockNativeAPI(returnsHandle: false)
        XCTAssertThrowsError(try SeekDB.open("/data", native: native)) { error in
            guard case SeekDBError.invalidNativeData = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testOptionsCopyBorrowedStringsAndPreserveUnusedNulls() throws {
        let native = MockNativeAPI()
        native.setOptions(transport: "unix_socket", socket: "/数据库/🦉/sql.sock")
        let db = try SeekDB.open("/data", native: native)
        let options = try db.connectionOptions()
        // Closing releases the mock's backing C strings, just as the C handle does.
        try db.close()
        XCTAssertEqual(options.transport, "unix_socket")
        XCTAssertEqual(options.unix_socket, "/数据库/🦉/sql.sock")
        XCTAssertEqual(options.user, "root")
        XCTAssertEqual(options.port, 0)
        XCTAssertNil(options.host)
        XCTAssertNil(options.named_pipe)
    }

    func testOptionsPreserveTCPAndFutureTransportFields() throws {
        let native = MockNativeAPI()
        native.setOptions(transport: "future_transport", host: "::1", port: 2881)
        let db = try SeekDB.open("/data", native: native)
        let options = try db.connectionOptions()
        XCTAssertEqual(options.transport, "future_transport")
        XCTAssertEqual(options.host, "::1")
        XCTAssertEqual(options.port, 2881)
        try db.close()
    }

    func testOptionsRejectMissingOrInvalidUTF8Transport() throws {
        for invalidUTF8 in [false, true] {
            let native = MockNativeAPI()
            native.setMissingOrInvalidTransport(invalidUTF8: invalidUTF8)
            let db = try SeekDB.open("/data", native: native)
            XCTAssertThrowsError(try db.connectionOptions()) { error in
                guard case SeekDBError.invalidNativeData = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
            try db.close()
        }
    }

    func testOptionsPropagateNativeFailure() throws {
        let native = MockNativeAPI(optionsCode: -29)
        let db = try SeekDB.open("/data", native: native)
        XCTAssertThrowsError(try db.connectionOptions()) { error in
            guard let nativeError = error as? SeekDBError,
                  case .native(operation: .connectionOptions, code: -29, message: _) = nativeError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        try db.close()
    }

    func testCloseIsIdempotentAndClosedOptionsNeverCallNative() throws {
        let native = MockNativeAPI()
        var db: SeekDB? = try SeekDB.open("/data", native: native)
        try db!.close()
        try db!.close()
        XCTAssertThrowsError(try db!.connectionOptions()) { error in
            XCTAssertEqual(error as? SeekDBError, .closed)
        }
        db = nil
        XCTAssertEqual(native.closeCount, 1)
        XCTAssertEqual(native.optionsCount, 0)
    }

    func testFailedCloseRetainsHandleForRetry() throws {
        let native = MockNativeAPI(closeCodes: [-31, 0])
        let db = try SeekDB.open("/data", native: native)
        XCTAssertThrowsError(try db.close()) { error in
            guard let nativeError = error as? SeekDBError,
                  case .native(operation: .close, code: -31, message: _) = nativeError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try db.connectionOptions().transport, "unix_socket")
        try db.close()
        try db.close()
        XCTAssertEqual(native.closeCount, 2)
    }

    func testDeinitClosesAnOpenHandle() throws {
        let native = MockNativeAPI()
        var db: SeekDB? = try SeekDB.open("/data", native: native)
        XCTAssertNotNil(db)
        db = nil
        XCTAssertEqual(native.closeCount, 1)
    }

    func testOptionsAndCloseCannotRaceNativeStringLifetime() throws {
        let native = MockNativeAPI(blockOptions: true)
        let db = try SeekDB.open("/data", native: native)
        let readDone = expectation(description: "options copied")
        let closeDone = expectation(description: "handle closed")
        let closeRequested = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            defer { readDone.fulfill() }
            do {
                let options = try db.connectionOptions()
                XCTAssertEqual(options.user, "root")
            } catch {
                XCTFail("Options retrieval failed: \(error)")
            }
        }
        XCTAssertEqual(native.optionsEntered.wait(timeout: .now() + 2), .success)
        DispatchQueue.global().async {
            defer { closeDone.fulfill() }
            closeRequested.signal()
            do {
                try db.close()
            } catch {
                XCTFail("Concurrent close failed: \(error)")
            }
        }
        XCTAssertEqual(closeRequested.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(native.closeEntered.wait(timeout: .now() + .milliseconds(100)), .timedOut,
                       "close must not invalidate borrowed strings during options retrieval")
        native.optionsMayReturn.signal()
        wait(for: [readDone, closeDone], timeout: 3)
        XCTAssertEqual(native.closeCount, 1)
    }
}

/// Mutable test setup precedes all concurrent use; counters and buffers share a lock.
private final class MockNativeAPI: NativeAPI, @unchecked Sendable {
    private let lock = NSLock()
    private let openCode: Int32
    private let optionsCode: Int32
    private let returnsHandle: Bool
    private let blockOptions: Bool
    private var closeCodes: [Int32]
    private var strings: [NativeCString] = []
    private var options = NativeConnectionOptions()
    private var opens = 0
    private var reads = 0
    private var closes = 0
    private var directory: String?
    private var parameters: [String]?
    var openError = "native open failure"
    let optionsEntered = DispatchSemaphore(value: 0)
    let optionsMayReturn = DispatchSemaphore(value: 0)
    let closeEntered = DispatchSemaphore(value: 0)

    init(openCode: Int32 = 0, optionsCode: Int32 = 0, returnsHandle: Bool = true,
         closeCodes: [Int32] = [0], blockOptions: Bool = false) {
        self.openCode = openCode
        self.optionsCode = optionsCode
        self.returnsHandle = returnsHandle
        self.closeCodes = closeCodes
        self.blockOptions = blockOptions
        setOptions(transport: "unix_socket", socket: "/data/run/sql.sock")
    }

    var openCount: Int { locked { opens } }
    var optionsCount: Int { locked { reads } }
    var closeCount: Int { locked { closes } }
    var openDirectory: String? { locked { directory } }
    var openParameters: [String]? { locked { parameters } }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func store(_ value: String?) -> UnsafePointer<CChar>? {
        guard let value else { return nil }
        let string = NativeCString(value)
        strings.append(string)
        return UnsafePointer(string.buffer)
    }

    func setOptions(transport: String, host: String? = nil, port: UInt32 = 0, socket: String? = nil) {
        locked {
            strings.removeAll()
            options = NativeConnectionOptions(transport: store(transport), port: port,
                                              host: store(host), unix_socket: store(socket),
                                              user: store("root"))
        }
    }

    func setMissingOrInvalidTransport(invalidUTF8: Bool) {
        locked {
            if invalidUTF8 {
                // Keep ownership in strings but replace the first byte with an
                // invalid UTF-8 leading byte. The allocation stays NUL terminated.
                let string = NativeCString("x")
                string.buffer[0] = CChar(bitPattern: 0xff)
                strings.append(string)
                options.transport = UnsafePointer(string.buffer)
            } else {
                options.transport = nil
            }
        }
    }

    func open(dbDir: String, parameters: [String]) -> (code: Int32, handle: UnsafeMutableRawPointer?) {
        locked {
            opens += 1
            directory = dbDir
            self.parameters = parameters
            return (openCode, openCode == 0 && returnsHandle ? UnsafeMutableRawPointer(bitPattern: 1) : nil)
        }
    }

    func lastOpenError() -> String { openError }

    func connectionOptions(handle: UnsafeMutableRawPointer) -> (code: Int32, options: NativeConnectionOptions) {
        if blockOptions {
            optionsEntered.signal()
            _ = optionsMayReturn.wait(timeout: .now() + 3)
        }
        return locked {
            reads += 1
            return (optionsCode, options)
        }
    }

    func close(handle: UnsafeMutableRawPointer) -> Int32 {
        closeEntered.signal()
        return locked {
            closes += 1
            let code = closeCodes.isEmpty ? 0 : closeCodes.removeFirst()
            if code == 0 {
                strings.removeAll()
                options = NativeConnectionOptions()
            }
            return code
        }
    }
}

#if os(iOS)
private func mysqlProtocolVersion(at path: String) throws -> UInt8 {
    let client = socket(AF_UNIX, SOCK_STREAM, 0)
    guard client >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    defer { close(client) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw POSIXError(.ENAMETOOLONG) }
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(client, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    var header = [UInt8](repeating: 0, count: 5)
    var received = 0
    while received < header.count {
        let count = header.withUnsafeMutableBytes { buffer in
            recv(client, buffer.baseAddress! + received, buffer.count - received, 0)
        }
        guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ECONNRESET) }
        received += count
    }
    return header[4]
}
#endif
