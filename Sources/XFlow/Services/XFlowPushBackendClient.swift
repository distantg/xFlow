import Foundation

struct XFlowPushBackendClient {
    private let defaults = UserDefaults.standard
    private let endpointDefaultsKey = "xflow.pushBackendURL"
    private let legacyEndpointDefaultsKey = "xdeck.pushBackendURL"

    func syncDeviceMapping(deviceToken: String, accounts: [DeckAccount], activeAccountID: UUID) {
        guard let endpoint = endpointURL() else {
            return
        }

        let payload = DeviceSyncPayload(
            bundleID: Bundle.main.bundleIdentifier ?? "com.distantg.xflow",
            platform: "macos",
            deviceToken: deviceToken,
            activeAccountID: activeAccountID.uuidString,
            accounts: accounts.map {
                .init(
                    id: $0.id.uuidString,
                    handle: $0.handle,
                    fallbackName: $0.fallbackName
                )
            }
        )

        Task.detached(priority: .utility) {
            do {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(payload)
                _ = try await URLSession.shared.data(for: request)
            } catch {
                NSLog("xFlow push sync failed: \(error.localizedDescription)")
            }
        }
    }

    private func endpointURL() -> URL? {
        if let fromEnvironment = ProcessInfo.processInfo.environment["XFLOW_PUSH_BACKEND_URL"],
           let parsed = URL(string: fromEnvironment) {
            return parsed
        }

        if let fromDefaults = defaults.string(forKey: endpointDefaultsKey)
            ?? defaults.string(forKey: legacyEndpointDefaultsKey),
           let parsed = URL(string: fromDefaults) {
            return parsed
        }

        return nil
    }
}

private struct DeviceSyncPayload: Encodable {
    struct Account: Encodable {
        let id: String
        let handle: String?
        let fallbackName: String
    }

    let bundleID: String
    let platform: String
    let deviceToken: String
    let activeAccountID: String
    let accounts: [Account]
}
