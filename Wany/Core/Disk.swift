import Foundation
import CryptoKit
import Security

struct Disk {
    static let root: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Wany", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        var value = URLResourceValues(); value.isExcludedFromBackup = true
        var mutable = u; try? mutable.setResourceValues(value)
        return u
    }()
    static func hash(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).map { String(format:"%02x", $0) }.joined() }
    static func folder(_ owner: String) -> URL { root.appendingPathComponent(hash(owner), isDirectory: true) }
    static func file(_ owner: String, _ name: String) -> URL { folder(owner).appendingPathComponent(name) }
    static func read<T: Decodable>(_ type: T.Type, owner: String, name: String) -> T? {
        guard let data = try? Data(contentsOf: file(owner, name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    static func save<T: Encodable>(_ value: T, owner: String, name: String) throws {
        let u = file(owner, name)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: u, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func imageName(_ chapterID: String, _ index: Int) -> String { "pages/" + hash(chapterID) + "/\(index).image" }
    static func coverName(_ key: String) -> String { "covers/" + hash(key) + ".image" }
    static func chapterName(_ id: String) -> String { "chapters/" + hash(id) + ".json" }
}

// Session credentials live in Keychain, not UserDefaults or the account cache.
enum Keychain {
    static func save(_ value: Data, key: String) throws {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"site.wany.ios", kSecAttrAccount as String:key]
        SecItemDelete(query as CFDictionary)
        var add = query; add[kSecValueData as String] = value
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain:NSOSStatusErrorDomain, code:Int(status)) }
    }
    static func read(_ key: String) -> Data? {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"site.wany.ios",kSecAttrAccount as String:key,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var out: CFTypeRef?; guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }
    static func delete(_ key: String) { SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"site.wany.ios",kSecAttrAccount as String:key] as CFDictionary) }
}
