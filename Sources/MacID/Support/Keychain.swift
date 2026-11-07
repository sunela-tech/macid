import CryptoKit
import Foundation
import Security

/// Minimal generic-password Keychain wrapper.
enum Keychain {
  static let service = "app.macid.MacID"

  static func set(_ data: Data, for account: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let update: [String: Any] = [kSecValueData as String: data]
    let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
    if status == errSecItemNotFound {
      var add = query
      add[kSecValueData as String] = data
      SecItemAdd(add as CFDictionary, nil)
    }
  }

  static func get(_ account: String) -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
    return result as? Data
  }

  static func delete(_ account: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
  }
}

/// Encrypts small files at rest with an AES-GCM key kept in the Keychain.
enum SecureFile {
  private static let keyAccount = "storage-key"

  private static var key: SymmetricKey {
    if let raw = Keychain.get(keyAccount), raw.count == 32 {
      return SymmetricKey(data: raw)
    }
    let fresh = SymmetricKey(size: .bits256)
    Keychain.set(fresh.withUnsafeBytes { Data($0) }, for: keyAccount)
    return fresh
  }

  static func write(_ data: Data, to url: URL) throws {
    let sealed = try AES.GCM.seal(data, using: key)
    guard let combined = sealed.combined else { throw CocoaError(.fileWriteUnknown) }
    try combined.write(to: url, options: .atomic)
  }

  static func read(_ url: URL) throws -> Data {
    let combined = try Data(contentsOf: url)
    let box = try AES.GCM.SealedBox(combined: combined)
    return try AES.GCM.open(box, using: key)
  }
}
