import Network
import Observation

@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    var isConnected = true
    var connectionType: NWInterface.InterfaceType?

    @ObservationIgnored
    private let monitor = NWPathMonitor()

    @ObservationIgnored
    private let queue = DispatchQueue(label: "com.cutsense.networkmonitor")

    @ObservationIgnored
    nonisolated(unsafe) private static var _active: NetworkMonitor?

    private init() {
        Self._active = self
        Self.installCallback(on: monitor)
        monitor.start(queue: queue)
    }

    nonisolated private static func installCallback(on monitor: NWPathMonitor) {
        monitor.pathUpdateHandler = { path in
            let isConnected = path.status == .satisfied
            let connectionType = path.availableInterfaces.first?.type
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    Self._active?.isConnected = isConnected
                    Self._active?.connectionType = connectionType
                }
            }
        }
    }
}
