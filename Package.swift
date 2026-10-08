// swift-tools-version: 5.9
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

import PackageDescription

let package = Package(
    name: "seekdb-bindings",
    platforms: [.macOS(.v13), .iOS("18.0")],
    products: [.library(name: "SeekDB", targets: ["SeekDB"])],
    targets: [
        .target(
            name: "CSeekDB",
            path: "lib",
            sources: ["src/ios"],
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("seekdb", .when(platforms: [.macOS, .linux]))
            ]
        ),
        .target(
            name: "SeekDB",
            dependencies: ["CSeekDB"],
            path: "swift/Sources/SeekDB"
        ),
        .testTarget(
            name: "SeekDBTests",
            dependencies: ["SeekDB"],
            path: "swift/Tests/SeekDBTests"
        )
    ],
    cLanguageStandard: .c11
)
