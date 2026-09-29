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

import CSeekDB

/// Native strings are borrowed from the handle until its next close.
internal struct NativeConnectionOptions {
    var transport: UnsafePointer<CChar>?
    var port: UInt32 = 0
    var host: UnsafePointer<CChar>?
    var unix_socket: UnsafePointer<CChar>?
    var named_pipe: UnsafePointer<CChar>?
    var user: UnsafePointer<CChar>?
}

/// Injectable at the native boundary to test ownership without starting an engine.
internal protocol NativeAPI: Sendable {
    func open(dbDir: String, parameters: [String]) -> (code: Int32, handle: UnsafeMutableRawPointer?)
    func lastOpenError() -> String
    func connectionOptions(handle: UnsafeMutableRawPointer) -> (code: Int32, options: NativeConnectionOptions)
    /// A nonzero result must leave the handle valid for a later close attempt.
    func close(handle: UnsafeMutableRawPointer) -> Int32
}

internal struct SystemNativeAPI: NativeAPI {
    func open(dbDir: String, parameters: [String]) -> (code: Int32, handle: UnsafeMutableRawPointer?) {
        // Each allocation owns stable UTF-8 storage throughout the native call;
        // building the pointer array never borrows temporary withCString buffers.
        let strings = parameters.map(NativeCString.init)
        var pointers: [UnsafePointer<CChar>?] = strings.map { UnsafePointer($0.buffer) }
        pointers.append(nil)
        var handle: SeekdbHandle?
        let code = withExtendedLifetime(strings) {
            dbDir.withCString { directory in
                if parameters.isEmpty {
                    return seekdb_open(directory, nil, &handle)
                }
                return pointers.withUnsafeMutableBufferPointer { buffer in
                    seekdb_open(directory, buffer.baseAddress, &handle)
                }
            }
        }
        return (code, handle)
    }

    func lastOpenError() -> String {
        guard let error = seekdb_last_open_error() else { return "Native open failed without a description" }
        return String(validatingCString: error) ?? "Native error description is not valid UTF-8"
    }

    func connectionOptions(handle: UnsafeMutableRawPointer) -> (code: Int32, options: NativeConnectionOptions) {
        var options = SeekdbConnectionOptions()
        let code = seekdb_connection_options(handle, &options)
        return (code, NativeConnectionOptions(
            transport: options.transport, port: options.port, host: options.host,
            unix_socket: options.unix_socket, named_pipe: options.named_pipe, user: options.user
        ))
    }

    func close(handle: UnsafeMutableRawPointer) -> Int32 {
        seekdb_close(handle)
    }
}

internal final class NativeCString {
    let buffer: UnsafeMutablePointer<CChar>

    init(_ value: String) {
        let bytes = value.utf8CString
        buffer = .allocate(capacity: bytes.count)
        bytes.withUnsafeBufferPointer { source in
            buffer.initialize(from: source.baseAddress!, count: source.count)
        }
    }

    deinit {
        buffer.deallocate()
    }
}
