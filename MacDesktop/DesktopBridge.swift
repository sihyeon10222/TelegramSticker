import Foundation

@MainActor
@objc(SBDesktopPluginProtocol)
protocol DesktopPluginProtocol {
    func start(snapshot: @escaping () -> [NSDictionary], copy: @escaping (String) -> String?, openManagement: @escaping () -> Void)
    func updateSnapshot(_ snapshot: [NSDictionary])
    func setLibraryStatus(_ message: String?)
    func writeGIFToPasteboard(_ data: Data) throws
    func showManagement()
    func togglePicker()
    func settings() -> NSDictionary
    func setLoginEnabled(_ enabled: Bool)
    func recordShortcut()
    func setMenuVisible(_ visible: Bool)
}
