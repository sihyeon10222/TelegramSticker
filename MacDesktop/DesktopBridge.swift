import Foundation

@MainActor
@objc(SBDesktopPluginProtocol)
protocol DesktopPluginProtocol {
    func start(snapshot: @escaping () -> [NSDictionary], copy: @escaping (String) -> String?, openManagement: @escaping () -> Void)
    func showManagement()
    func togglePicker()
    func settings() -> NSDictionary
    func setLoginEnabled(_ enabled: Bool)
    func setMenuVisible(_ visible: Bool)
}
