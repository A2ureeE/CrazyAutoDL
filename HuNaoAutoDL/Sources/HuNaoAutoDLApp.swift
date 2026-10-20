import AppKit
import SwiftUI

@main
struct HuNaoAutoDLApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("胡闹AutoDL", id: "main") {
            RootView()
                .environmentObject(model)
                .environmentObject(model.updater)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1_220, height: 820)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .appInfo) {
                Button("检查更新…") {
                    model.selectedSection = .settings
                    MenuBarController.shared.reopenMainWindow()
                    Task { await model.updater.check() }
                }
                .disabled(model.updater.isBusy)

                Divider()
            }

            CommandMenu("监控") {
                Button("立即刷新") {
                    model.refreshNow()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("打开 AutoDL 控制台") {
                    if let url = URL(string: "https://www.autodl.com/console/instance/list") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Divider()

                Button("退出登录") {
                    model.logout()
                }
                .disabled(model.phase != .signedIn)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppBrand.icon
        NotificationService.shared.activate()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MenuBarController.shared.reopenMainWindow()
        }
        return true
    }
}
