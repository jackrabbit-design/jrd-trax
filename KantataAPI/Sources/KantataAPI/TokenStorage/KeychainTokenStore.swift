import Foundation
import Security

public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String
    private let secItemStore: any SecItemStore

    public init(
        service: String = "com.jumpingjackrabbit.trax.oauth",
        account: String = "kantata",
        secItemStore: any SecItemStore = KeychainSecItemStore()
    ) {
        self.service = service
        self.account = account
        self.secItemStore = secItemStore
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    public func save(_ token: OAuthToken) throws {
        let data = try JSONEncoder().encode(token)
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = secItemStore.add(addQuery)
        if addStatus == errSecDuplicateItem {
            let updateStatus = secItemStore.update(query: baseQuery, attributesToUpdate: [kSecValueData as String: data])
            guard updateStatus == errSecSuccess else { throw KeychainError.status(updateStatus) }
        } else if addStatus != errSecSuccess {
            throw KeychainError.status(addStatus)
        }
    }

    public func load() throws -> OAuthToken? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, result) = secItemStore.copyMatching(query)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.status(status)
        }
        return try JSONDecoder().decode(OAuthToken.self, from: data)
    }

    public func delete() throws {
        let status = secItemStore.delete(baseQuery)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}
