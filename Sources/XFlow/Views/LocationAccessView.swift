import AppKit
import CoreLocation
import SwiftUI

@MainActor
final class LocationAuthorization: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus = .notDetermined
    private let manager = CLLocationManager()

    override init() {
        super.init()
        status = manager.authorizationStatus
        manager.delegate = self
    }

    func request() {
        // Only called from the user-opened location sheet, never at app launch.
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
    }

    var isAllowed: Bool { status == .authorizedAlways }
}

struct LocationAccessView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authorization = LocationAuthorization()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Location", systemImage: "location") .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(MosaicButtonStyle(kind: .quiet, cornerRadius: 12, compact: true))
            }
            Text(authorization.isAllowed ? "Location access is allowed" : "Allow Mosaic to use your location")
                .font(.headline)
            Text(authorization.isAllowed
                 ? "macOS permission is enabled. You choose whether to include a location in each post."
                 : "Use the macOS prompt to grant access. If access was denied or Location Services is off, you can change it in System Settings.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Open Location Services") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
            }
            .buttonStyle(MosaicButtonStyle(kind: .quiet, cornerRadius: 12, compact: true))
            Divider()
            Text("Enable location tagging in X").font(.headline)
            Text("If Tag location is disabled, open X’s Settings and privacy → Privacy and safety → Location information → Add location information to your Posts. Then reopen the composer.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Granting macOS access does not turn on X’s account setting or add a location to your post.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(26)
        .frame(width: 430)
        .background(.regularMaterial)
        .onAppear { authorization.request() }
    }
}
