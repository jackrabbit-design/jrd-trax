import Testing
import Foundation
import Security
@testable import KantataAPI

final class FakeSecItemStore: SecItemStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]

    func add(_ attributes: [String: Any]) -> OSStatus {
        let account = attributes[kSecAttrAccount as String] as! String
        if storage[account] != nil { return errSecDuplicateItem }
        storage[account] = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func update(query: [String: Any], attributesToUpdate: [String: Any]) -> OSStatus {
        let account = query[kSecAttrAccount as String] as! String
        guard storage[account] != nil else { return errSecItemNotFound }
        storage[account] = attributesToUpdate[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func copyMatching(_ query: [String: Any]) -> (OSStatus, AnyObject?) {
        let account = query[kSecAttrAccount as String] as! String
        guard let data = storage[account] else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, data as AnyObject)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        let account = query[kSecAttrAccount as String] as! String
        guard storage[account] != nil else { return errSecItemNotFound }
        storage.removeValue(forKey: account)
        return errSecSuccess
    }
}

@Suite("Keychain token store")
struct KeychainTokenStoreTests {
    private func makeToken() -> OAuthToken {
        OAuthToken(accessToken: "tok", tokenType: "Bearer", scope: "read", refreshToken: nil, createdAt: Date(timeIntervalSince1970: 0))
    }

    @Test("load returns nil when nothing has been saved")
    func loadEmpty() throws {
        let store = KeychainTokenStore(secItemStore: FakeSecItemStore())
        #expect(try store.load() == nil)
    }

    @Test("save then load round-trips the token")
    func saveThenLoad() throws {
        let store = KeychainTokenStore(secItemStore: FakeSecItemStore())
        let token = makeToken()
        try store.save(token)
        #expect(try store.load() == token)
    }

    @Test("saving twice updates rather than duplicating")
    func saveTwiceUpdates() throws {
        let store = KeychainTokenStore(secItemStore: FakeSecItemStore())
        try store.save(makeToken())
        let updated = OAuthToken(accessToken: "tok2", tokenType: "Bearer", scope: nil, refreshToken: nil, createdAt: Date(timeIntervalSince1970: 100))
        try store.save(updated)
        #expect(try store.load() == updated)
    }

    @Test("delete removes the token")
    func deleteRemoves() throws {
        let store = KeychainTokenStore(secItemStore: FakeSecItemStore())
        try store.save(makeToken())
        try store.delete()
        #expect(try store.load() == nil)
    }

    @Test("deleting when nothing exists does not throw")
    func deleteWhenEmpty() throws {
        let store = KeychainTokenStore(secItemStore: FakeSecItemStore())
        try store.delete()
    }
}
