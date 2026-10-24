import Foundation

enum FilePath {
    static let groupName = "group.test.woman-in-red"
    static let workingDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("woman-in-red-vpn-manager-tests", isDirectory: true)
}

extension Bundle {
    var baseBundleIdentifier: String {
        "com.womaninred.test"
    }
}
