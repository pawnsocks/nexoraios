import Combine
import Network
import Foundation

@MainActor final class Connectivity: ObservableObject {
    @Published var online = true
    private let monitor = NWPathMonitor()
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.online = path.status == .satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "nexora.connectivity"))
    }
    deinit { monitor.cancel() }
}
