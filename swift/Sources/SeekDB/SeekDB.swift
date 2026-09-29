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

import Foundation

/// A copied snapshot of the native endpoint, independent of any SQL client driver.
///
/// Unused transport fields are nil. Keeping this value does not keep the native
/// instance alive: establish client connections only while its SeekDB is open.
public struct ConnectionOptions: Equatable, Sendable {
    public let transport: String
    public let port: UInt32
    public let host: String?
    public let unix_socket: String?
    public let named_pipe: String?
    public let user: String?
}

/// Validation, lifecycle, and native errors reported by the instance API.
public enum SeekDBError: Error, Equatable, Sendable {
    public enum Operation: String, Sendable {
        case open
        case connectionOptions
        case close
    }

    case invalidArgument(String)
    case closed
    case native(operation: Operation, code: Int32, message: String)
    case invalidNativeData(String)
}

extension SeekDBError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidArgument(let message), .invalidNativeData(let message):
            return message
        case .closed:
            return "SeekDB is closed"
        case .native(let operation, let code, let message):
            return "SeekDB \(operation.rawValue) failed (code=\(code)): \(message)"
        }
    }
}

/// Owns a local SeekDB instance handle; SQL clients are configured separately.
///
/// Opening and closing are synchronous and can block. Call them away from an
/// application's UI thread. Close SQL clients before closing this handle.
/// Operations on one handle are serialized, including copying native strings.
public final class SeekDB: @unchecked Sendable {
    private let lock = NSLock()
    private let native: any NativeAPI
    private var handle: UnsafeMutableRawPointer?

    private init(handle: UnsafeMutableRawPointer, native: any NativeAPI) {
        self.handle = handle
        self.native = native
    }

    /// Open a writable, persistent database directory with optional alternating
    /// parameter names and values. Native defaults apply when parameters is empty.
    /// Parameter values are passed unchanged; empty values are allowed.
    public static func open(_ dbDir: String, parameters: [String] = []) throws -> SeekDB {
        try open(dbDir, parameters: parameters, native: SystemNativeAPI())
    }

    internal static func open(
        _ dbDir: String, parameters: [String] = [], native: any NativeAPI
    ) throws -> SeekDB {
        guard !dbDir.isEmpty, !dbDir.utf8.contains(0) else {
            throw SeekDBError.invalidArgument("Database directory must be non-empty and contain no NUL bytes")
        }
        guard parameters.count.isMultiple(of: 2) else {
            throw SeekDBError.invalidArgument("Parameters must be key/value pairs")
        }
        for (index, parameter) in parameters.enumerated() {
            guard !parameter.utf8.contains(0), index % 2 != 0 || !parameter.isEmpty else {
                throw SeekDBError.invalidArgument("Parameter keys must be non-empty and parameters must contain no NUL bytes")
            }
        }
        let result = native.open(dbDir: dbDir, parameters: parameters)
        guard result.code == 0 else {
            // The error is thread-local and borrowed; copy it on this same thread
            // before any other native operation can replace it.
            let message = native.lastOpenError()
            throw SeekDBError.native(operation: .open, code: result.code, message: message)
        }
        guard let handle = result.handle else {
            throw SeekDBError.invalidNativeData("Native open succeeded without returning a handle")
        }
        return SeekDB(handle: handle, native: native)
    }

    /// Return copied endpoint fields. The endpoint itself is usable only while
    /// this handle is open, even though these Swift strings retain their values.
    public func connectionOptions() throws -> ConnectionOptions {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { throw SeekDBError.closed }
        let result = native.connectionOptions(handle: handle)
        guard result.code == 0 else {
            throw SeekDBError.native(operation: .connectionOptions, code: result.code,
                                     message: "Cannot obtain native connection options")
        }
        func copy(_ value: UnsafePointer<CChar>?, field: String) throws -> String? {
            guard let value else { return nil }
            guard let string = String(validatingCString: value) else {
                throw SeekDBError.invalidNativeData("Native \(field) is not valid UTF-8")
            }
            return string
        }
        guard let transport = try copy(result.options.transport, field: "transport") else {
            throw SeekDBError.invalidNativeData("Native connection options have no transport")
        }
        return try ConnectionOptions(
            transport: transport,
            port: result.options.port,
            host: copy(result.options.host, field: "host"),
            unix_socket: copy(result.options.unix_socket, field: "unix_socket"),
            named_pipe: copy(result.options.named_pipe, field: "named_pipe"),
            user: copy(result.options.user, field: "user")
        )
    }

    /// Release the handle, without deleting database files. Repeated successful
    /// closes are harmless. On failure the handle stays open so close can be retried.
    /// Whether this waits for engine shutdown depends on the native platform adapter.
    public func close() throws {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { return }
        let code = native.close(handle: handle)
        guard code == 0 else {
            throw SeekDBError.native(operation: .close, code: code,
                                     message: "Cannot close the native instance handle")
        }
        self.handle = nil
    }

    deinit {
        try? close()
    }
}
