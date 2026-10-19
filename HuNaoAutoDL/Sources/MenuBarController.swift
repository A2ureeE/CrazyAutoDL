import AppKit
import Combine
import SwiftUI

struct MenuBarBridge: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                MenuBarController.shared.attach(model: model) {
                    openWindow(id: "main")
                    DispatchQueue.main.async {
                        NSApp.windows
                            .first(where: { $0.canBecomeMain && !($0 is NSPanel) })?
                            .makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            }
    }
}

@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var quickPanel: NSPopover?
    private var model: AppModel?
    private var openMainWindow: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()

    private enum Mode {
        case disconnected
        case monitoring
        case running
        case crazy

        var symbol: String {
            switch self {
            case .disconnected: return "pause.circle.fill"
            case .monitoring: return "eye.fill"
            case .running: return "bolt.fill"
            case .crazy: return "flame.fill"
            }
        }

        var label: String {
            switch self {
            case .disconnected: return "等待连接"
            case .monitoring: return "监控中"
            case .running: return "运行中"
            case .crazy: return "疯狂模式"
            }
        }
    }

    func attach(model: AppModel, openMainWindow: @escaping () -> Void) {
        self.model = model
        self.openMainWindow = openMainWindow

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.imagePosition = .imageOnly
            statusItem = item
        }

        if let button = statusItem?.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        guard cancellables.isEmpty else {
            refresh()
            return
        }
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refresh() }
            }
            .store(in: &cancellables)
        refresh()
    }

    func reopenMainWindow() {
        if let openMainWindow {
            openMainWindow()
        } else {
            NSApp.windows
                .first(where: { $0.canBecomeMain && !($0 is NSPanel) })?
                .makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var currentMode: Mode {
        guard let model, model.phase == .signedIn else { return .disconnected }
        if model.autoStartEnabled { return .crazy }
        if model.runningCount > 0 { return .running }
        return .monitoring
    }

    private func refresh() {
        guard let model, let button = statusItem?.button else { return }
        let mode = currentMode

        let color = Self.color(for: mode)

        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        if let image = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: mode.label)?
            .withSymbolConfiguration(configuration) {
            image.isTemplate = false
            button.image = image
        }

        var tooltip = "胡闹AutoDL · \(mode.label)"
        if model.phase == .signedIn {
            tooltip += "\n\(model.runningCount)/\(model.instances.count) 台实例运行中 · 余额 \(model.balanceLabel)"
        }
        tooltip += "\n左键打开快捷面板 · 右键更多菜单"
        button.toolTip = tooltip
        resizeQuickPanelIfNeeded()
    }

    private static func color(for mode: Mode) -> NSColor {
        switch mode {
        case .disconnected:
            return .secondaryLabelColor
        case .monitoring:
            return dynamicColor(dark: (0.33, 0.81, 1.00), light: (0.02, 0.45, 0.72))
        case .running:
            return dynamicColor(dark: (0.38, 0.98, 0.76), light: (0.00, 0.50, 0.32))
        case .crazy:
            return dynamicColor(dark: (1.00, 0.65, 0.24), light: (0.84, 0.34, 0.02))
        }
    }

    // MARK: - Quick Panel

    @objc private func statusItemClicked() {
        guard let model else { return }

        if NSApp.currentEvent?.type == .rightMouseUp {
            closeQuickPanel()
            showContextMenu(for: model)
        } else {
            toggleQuickPanel(for: model)
        }
    }

    private func toggleQuickPanel(for model: AppModel) {
        if let quickPanel, quickPanel.isShown {
            closeQuickPanel()
            return
        }

        closeQuickPanel()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self

        let root = QuickPanelView(
            onOpenDashboard: { [weak self] in
                self?.closeQuickPanel()
                self?.reopenMainWindow()
            },
            onOpenConsole: { [weak self] in
                self?.closeQuickPanel()
                self?.openConsole()
            },
            onRefresh: { [weak self] in
                self?.model?.refreshNow()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
        .environmentObject(model)
        .environment(\.appFontScale, CGFloat(model.fontScale))

        let hosting = NSHostingController(rootView: root)
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.view.layoutSubtreeIfNeeded()

        let fitted = hosting.view.fittingSize
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 360, height: max(240, fitted.height))
        quickPanel = popover

        guard let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeQuickPanel() {
        guard let quickPanel else { return }
        self.quickPanel = nil
        quickPanel.performClose(nil)
    }

    private func resizeQuickPanelIfNeeded() {
        guard let quickPanel, quickPanel.isShown,
              let contentView = quickPanel.contentViewController?.view
        else { return }
        contentView.layoutSubtreeIfNeeded()
        let height = contentView.fittingSize.height
        guard height > 0, abs(height - quickPanel.contentSize.height) > 0.5 else { return }
        quickPanel.contentSize = NSSize(width: 360, height: max(240, height))
    }

    private func showContextMenu(for model: AppModel) {
        guard let button = statusItem?.button else { return }
        let mode = currentMode
        let menu = buildMenu(for: model, mode: mode, color: Self.color(for: mode))
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 5),
            in: button
        )
    }

    private func buildMenu(for model: AppModel, mode: Mode, color: NSColor) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let title = NSMenuItem(title: "胡闹AutoDL", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let statusLine: String
        if model.phase != .signedIn {
            statusLine = "未连接 · 打开窗口登录 AutoDL"
        } else if model.autoStartEnabled {
            statusLine = model.runningCount > 0
                ? "疯狂模式 · \(model.runningCount) 台运行中"
                : "疯狂模式 · 守候空闲显卡"
        } else if model.runningCount > 0 {
            statusLine = "运行中 · \(model.runningCount)/\(model.instances.count) 台实例"
        } else {
            statusLine = "监控中 · 每 \(Int(model.pollInterval)) 秒检查"
        }
        let status = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if model.phase == .signedIn {
            let balanceTitle = model.isLowBalance
                ? "余额偏低 · \(model.balanceLabel)"
                : "可用余额 · \(model.balanceLabel)"
            let balance = NSMenuItem(title: balanceTitle, action: nil, keyEquivalent: "")
            balance.isEnabled = false
            if model.isLowBalance {
                balance.attributedTitle = NSAttributedString(
                    string: balanceTitle,
                    attributes: [
                        .font: NSFont.menuFont(ofSize: 12),
                        .foregroundColor: Self.dynamicColor(
                            dark: (1.00, 0.76, 0.34),
                            light: (0.72, 0.38, 0.00)
                        )
                    ]
                )
            }
            menu.addItem(balance)
        }

        if let error = model.lastError, !error.isEmpty {
            let item = NSMenuItem(title: "同步异常：\(error)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.toolTip = error
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let open = NSMenuItem(title: "打开监控台", action: #selector(openMonitor), keyEquivalent: "o")
        open.target = self
        open.isEnabled = true
        menu.addItem(open)

        if model.phase == .signedIn {
            let auto = NSMenuItem(
                title: "自动开机（疯狂模式）",
                action: #selector(toggleAutoStart),
                keyEquivalent: ""
            )
            auto.target = self
            auto.state = model.autoStartEnabled ? .on : .off
            auto.isEnabled = true
            if model.autoStartEnabled {
                auto.attributedTitle = NSAttributedString(
                    string: "自动开机（疯狂模式）",
                    attributes: [
                        .font: NSFont.menuFont(ofSize: 13),
                        .foregroundColor: color
                    ]
                )
            }
            menu.addItem(auto)
        }

        let refresh = NSMenuItem(
            title: model.isRefreshing ? "正在同步…" : "立即刷新",
            action: #selector(refreshNow),
            keyEquivalent: "r"
        )
        refresh.target = self
        refresh.isEnabled = !model.isRefreshing && model.phase == .signedIn
        menu.addItem(refresh)

        let console = NSMenuItem(
            title: "打开 AutoDL 控制台",
            action: #selector(openConsole),
            keyEquivalent: ""
        )
        console.target = self
        console.isEnabled = true
        menu.addItem(console)

        let star = NSMenuItem(
            title: "GitHub · 给胡闹AutoDL 点个 Star",
            action: #selector(openRepository),
            keyEquivalent: ""
        )
        star.target = self
        star.isEnabled = true
        menu.addItem(star)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出胡闹AutoDL", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        quit.isEnabled = true
        menu.addItem(quit)

        return menu
    }

    private static func dynamicColor(
        dark: (CGFloat, CGFloat, CGFloat),
        light: (CGFloat, CGFloat, CGFloat)
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(
                calibratedRed: value.0,
                green: value.1,
                blue: value.2,
                alpha: 1
            )
        }
    }

    @objc private func openMonitor() {
        reopenMainWindow()
    }

    @objc private func toggleAutoStart() {
        guard let model else { return }
        model.setAutoStart(!model.autoStartEnabled)
    }

    @objc private func refreshNow() {
        model?.refreshNow()
    }

    @objc private func openConsole() {
        if let url = URL(string: "https://www.autodl.com/console/instance/list") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openRepository() {
        AppLinks.openRepository()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

extension MenuBarController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        quickPanel = nil
    }
}
