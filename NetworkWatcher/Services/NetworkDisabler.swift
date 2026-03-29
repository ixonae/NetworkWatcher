import Foundation

class NetworkDisabler {
    static func disableWiFi(interfaceName: String = "en0") {
        let script = "do shell script \"networksetup -setairportpower \(interfaceName) off\" with administrator privileges"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("Failed to disable WiFi: \(error)")
            }
        }
    }
}
