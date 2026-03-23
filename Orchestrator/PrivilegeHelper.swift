import Foundation
import AppKit

class PrivilegeHelper {
    static let shared = PrivilegeHelper()
    
    func isRunningAsRoot() -> Bool {
        return getuid() == 0 || geteuid() == 0
    }
    
    func restartWithElevation() {
        let bundlePath = Bundle.main.bundlePath
        guard !bundlePath.isEmpty else {
            print("[Privilege] Bundle path is empty")
            return
        }

        let escapedBundlePath = bundlePath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        set appPath to "\(escapedBundlePath)"
        do shell script "/usr/bin/open -n " & quoted form of appPath & " >/tmp/orchestrator-elevated.log 2>&1" with administrator privileges
        """

        let task = NSAppleScript(source: script)
        var error: NSDictionary?
        _ = task?.executeAndReturnError(&error)

        if let error = error {
            let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? 0
            if errorNumber != -128 {
                print("[Privilege] AppleScript error: \(error)")
            }
            return
        }

        waitForRelaunchAndTerminate()
    }

    private func waitForRelaunchAndTerminate() {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NSApplication.shared.terminate(nil)
            }
            return
        }

        let deadline = Date().addingTimeInterval(8.0)

        func poll() {
            let runningCount = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count
            if runningCount >= 2 {
                NSApplication.shared.terminate(nil)
                return
            }

            if Date() >= deadline {
                let alert = NSAlert()
                alert.messageText = "Could not relaunch automatically"
                alert.informativeText = "Authentication succeeded, but a new elevated instance did not appear. Please try Request Access again."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                poll()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            poll()
        }
    }
}

