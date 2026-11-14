import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let defaults = UserDefaults.standard
    private var controlItem: NSStatusItem!
    private var dividerItem: NSStatusItem!
    private var settingsController: SettingsController!
    private var collapseTimer: Timer?
    private var isMenuOpen = false
    private var isArranging = false
    private var nativeAssertion: Any?
    private var visibilityGeneration = 0
    private var refreshWork: DispatchWorkItem?
    private var hoverWork: DispatchWorkItem?
    private var hoverTimer: Timer?
    private var hoverNeedsExit = false
    private var recoveryShortcut: RecoveryShortcut?
    private(set) var isUpdating = false
    private(set) var statusMessage: String?
    private(set) var isCollapsed = false
    private(set) var arrangementWarning = false

    let usesNativeVisibility = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    var hasRecoveryShortcut: Bool { recoveryShortcut?.isRegistered == true }

    var expandOnHover: Bool {
        get { defaults.object(forKey: "expandOnHover") == nil || defaults.bool(forKey: "expandOnHover") }
        set {
            defaults.set(newValue, forKey: "expandOnHover")
            hoverWork?.cancel()
            hoverWork = nil
            refresh()
        }
    }

    var hiddenApplications: [String: String] {
        get { defaults.dictionary(forKey: "hiddenApplications") as? [String: String] ?? [:] }
        set {
            defaults.set(newValue, forKey: "hiddenApplications")
            statusMessage = nil
            refresh()
        }
    }

    var autoCollapseSeconds: Int {
        get {
            let value = defaults.integer(forKey: "autoCollapseSeconds")
            return [0, 10, 30, 60].contains(value) ? value : 0
        }
        set {
            defaults.set(newValue, forKey: "autoCollapseSeconds")
            scheduleCollapse()
        }
    }

    var collapseAtLaunch: Bool {
        get { defaults.bool(forKey: "collapseAtLaunch") }
        set { defaults.set(newValue, forKey: "collapseAtLaunch") }
    }

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep one instance so a second launch can always recover the settings window.
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: "local.vanya.MenuFold")
        if let existing = peers.first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [])
            NSApp.terminate(nil)
            return
        }

        configureApplicationMenu()
        if defaults.integer(forKey: "controlLayoutVersion") < 1 {
            defaults.removeObject(forKey: "NSStatusItem Preferred Position MenuFold.Toggle")
            defaults.set(1, forKey: "controlLayoutVersion")
        }
        createStatusItems()
        recoveryShortcut = RecoveryShortcut { [weak self] in self?.toggleCollapsed() }
        settingsController = SettingsController(app: self)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screenChanged),
            name: NSWorkspace.didWakeNotification, object: nil)
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationsChanged), name: name, object: nil)
        }

        if !defaults.bool(forKey: "hasLaunched") || (usesNativeVisibility && hiddenApplications.isEmpty) {
            defaults.set(true, forKey: "hasLaunched")
            showSettings()
        } else {
            // Let the system restore the user's menu-bar item order before changing widths.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self else { return }
                self.setCollapsed(self.collapseAtLaunch)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        collapseTimer?.invalidate()
        hoverWork?.cancel()
        hoverTimer?.invalidate()
        visibilityGeneration += 1
        if let nativeAssertion { MFReleaseVisibility(nativeAssertion) }
        if dividerItem != nil { dividerItem.length = 20 }
    }

    private func configureApplicationMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        let toggle = applicationMenu.addItem(withTitle: "展开或收起图标", action: #selector(toggleCollapsed), keyEquivalent: "b")
        toggle.keyEquivalentModifierMask = [.control, .option, .command]
        toggle.target = self
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        applicationMenu.addItem(.separator())
        let quit = applicationMenu.addItem(withTitle: "退出折叠菜单栏", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        NSApp.mainMenu = menu
    }

    private func createStatusItems() {
        createControlItem()

        dividerItem = NSStatusBar.system.statusItem(withLength: 20)
        dividerItem.autosaveName = "MenuFold.Divider"
        dividerItem.isVisible = !usesNativeVisibility
        if let button = dividerItem.button {
            button.image = NSImage(systemSymbolName: "line.diagonal", accessibilityDescription: "收纳分隔线")
            button.imagePosition = .imageTrailing
            button.target = self
            button.action = #selector(dividerClicked)
            button.toolTip = "按住 ⌘ 拖动图标到这条分隔线左侧，即可收纳"
            button.setAccessibilityLabel("收纳分隔线")
        }
        refresh()
        logControlPlacement()
    }

    private func createControlItem() {
        controlItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        controlItem.autosaveName = "MenuFold.Toggle"
        controlItem.behavior = []
        controlItem.isVisible = true
        if let button = controlItem.button {
            button.title = "收纳"
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityIdentifier("MenuFold.Toggle")
        }

    }

    @objc func restoreControlItem() {
        setCollapsed(false)
        NSStatusBar.system.removeStatusItem(controlItem)
        for key in ["NSStatusItem Preferred Position MenuFold.Toggle", "NSStatusItem Visible MenuFold.Toggle",
            "NSStatusItem VisibleCC MenuFold.Toggle"] {
            defaults.removeObject(forKey: key)
        }
        createControlItem()
        refresh()
        logControlPlacement()
    }

    private func logControlPlacement() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let item = self.controlItem else { return }
            let frame = item.button?.window?.frame ?? .zero
            NSLog("MenuFold control visible=%d frame=%@ bundle=%@", item.isVisible,
                NSStringFromRect(frame), Bundle.main.bundleIdentifier ?? "unknown")
        }
    }

    @objc private func statusClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.option) {
            showMenu(event: event)
        } else {
            toggleCollapsed()
        }
    }

    @objc private func dividerClicked() { showSettings() }

    private func showMenu(event: NSEvent) {
        let menu = NSMenu()
        menu.delegate = self
        let toggle = menu.addItem(withTitle: isCollapsed ? "展开收纳图标" : "收起收纳图标",
            action: #selector(toggleCollapsed), keyEquivalent: "")
        toggle.target = self
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: "设置与使用说明…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        let arrange = menu.addItem(withTitle: "开始整理图标…", action: #selector(startArranging), keyEquivalent: "")
        arrange.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "退出折叠菜单栏", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        if let button = controlItem.button { NSMenu.popUpContextMenu(menu, with: event, for: button) }
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        collapseTimer?.invalidate()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        scheduleCollapse()
    }

    @objc func toggleCollapsed() {
        if usesNativeVisibility && hiddenApplications.isEmpty {
            showSettings()
            settingsController.chooseApplications(collapseAfterSaving: true)
            return
        }
        setCollapsed(!isCollapsed)
    }

    private func updateHoverTimer() {
        guard expandOnHover, isCollapsed else {
            hoverTimer?.invalidate()
            hoverTimer = nil
            hoverWork?.cancel()
            hoverWork = nil
            return
        }
        guard hoverTimer == nil else { return }
        // A click to collapse stays collapsed until the pointer leaves and re-enters.
        hoverNeedsExit = isMouseOverControl
        hoverTimer = Timer.scheduledTimer(timeInterval: 0.15, target: self,
            selector: #selector(checkHover), userInfo: nil, repeats: true)
    }

    private var isMouseOverControl: Bool {
        controlItem.button?.window?.frame.insetBy(dx: -4, dy: 0).contains(NSEvent.mouseLocation) == true
    }

    @objc private func checkHover() {
        if !isMouseOverControl { hoverNeedsExit = false }
        guard expandOnHover, isCollapsed, !isUpdating, !isMenuOpen,
              isMouseOverControl, !hoverNeedsExit, NSEvent.pressedMouseButtons == 0 else {
            hoverWork?.cancel()
            hoverWork = nil
            return
        }
        guard hoverWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoverWork = nil
            guard self.expandOnHover, self.isCollapsed, self.isMouseOverControl,
                  NSEvent.pressedMouseButtons == 0 else { return }
            self.setCollapsed(false)
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    func setCollapsed(_ collapsed: Bool) {
        collapseTimer?.invalidate()
        statusMessage = nil
        if usesNativeVisibility {
            setNativeCollapsed(collapsed)
            return
        }
        arrangementWarning = collapsed && !hasValidOrder()
        isCollapsed = collapsed && !arrangementWarning
        if isCollapsed { isArranging = false }
        // A wide separator pushes the items on its left out of the visible menu bar.
        // The toggle on its right remains available to reveal them again.
        dividerItem.length = isCollapsed ? 10_000 : 20
        refresh()
        scheduleCollapse()
    }

    private func hasValidOrder() -> Bool {
        guard let dividerFrame = dividerItem.button?.window?.frame,
              let controlFrame = controlItem.button?.window?.frame else { return false }
        return dividerFrame.maxX <= controlFrame.minX + 2
    }

    private func setNativeCollapsed(_ collapsed: Bool) {
        visibilityGeneration += 1
        let generation = visibilityGeneration
        isUpdating = false
        if !collapsed {
            refreshWork?.cancel()
            if let nativeAssertion { MFReleaseVisibility(nativeAssertion) }
            nativeAssertion = nil
            isCollapsed = false
            refresh()
            scheduleCollapse()
            return
        }
        guard !hiddenApplications.isEmpty else {
            statusMessage = "请先选择要收纳的应用。"
            refresh()
            return
        }
        guard MFNativeVisibilityAvailable() else {
            statusMessage = "当前系统的收纳接口不可用。"
            refresh()
            return
        }
        isUpdating = true
        refresh()
        var allowed = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        allowed.subtract(hiddenApplications.keys)
        allowed.insert(Bundle.main.bundleIdentifier ?? "local.vanya.MenuFold")
        if let currentBundle = NSRunningApplication.current.bundleIdentifier { allowed.insert(currentBundle) }
        MFActivateVisibility(Array(allowed)) { [weak self] handle, error in
            MainActor.assumeIsolated {
                guard let self, self.visibilityGeneration == generation else {
                    if let handle { MFReleaseVisibility(handle) }
                    return
                }
                self.isUpdating = false
                if let handle {
                    let previous = self.nativeAssertion
                    self.nativeAssertion = handle
                    if let previous { MFReleaseVisibility(previous) }
                    self.isCollapsed = true
                    self.isArranging = false
                    NSLog("MenuFold visibility restriction activated for %ld selected application(s)", self.hiddenApplications.count)
                } else {
                    if let previous = self.nativeAssertion { MFReleaseVisibility(previous) }
                    self.nativeAssertion = nil
                    self.isCollapsed = false
                    self.statusMessage = "收纳失败，图标仍展开。\(error?.localizedDescription ?? "请重试。")"
                }
                self.refresh()
            }
        }
    }

    @objc private func applicationsChanged() {
        guard usesNativeVisibility, isCollapsed || isUpdating else { return }
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isCollapsed || self.isUpdating else { return }
            self.setNativeCollapsed(true)
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    @objc func showSettings() {
        setCollapsed(false)
        settingsController.show()
    }

    @objc func startArranging() {
        isArranging = true
        setCollapsed(false)
        settingsController.show()
        if usesNativeVisibility { settingsController.chooseApplications() }
        else { settingsController.showArrangementHint() }
    }

    func finishArranging() {
        isArranging = false
        toggleCollapsed()
    }

    func settingsClosed() {
        isArranging = false
        DispatchQueue.main.async { [weak self] in self?.scheduleCollapse() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval {
                let alert = NSAlert()
                alert.messageText = "请在系统设置中允许登录时启动"
                alert.informativeText = "打开“系统设置 → 通用 → 登录项与扩展”，允许折叠菜单栏在登录时启动。"
                alert.addButton(withTitle: "打开登录项")
                alert.addButton(withTitle: "稍后")
                if alert.runModal() == .alertFirstButtonReturn { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "未能更改登录项"
            alert.informativeText = "可先将应用放到“应用程序”文件夹后重试。\n\(error.localizedDescription)"
            alert.runModal()
        }
        settingsController.refresh()
    }

    private func refresh() {
        let label = isCollapsed ? "展开收纳图标" : "收起收纳图标"
        controlItem.button?.image = NSImage(systemSymbolName: isUpdating ? "ellipsis" : (isCollapsed ? "chevron.left" : "chevron.right"),
            accessibilityDescription: label)
        controlItem.button?.toolTip = expandOnHover
            ? "悬停“收纳”展开图标 · 点击切换 · 右键打开设置"
            : "点击“收纳”展开或收起 · 右键打开设置"
        controlItem.button?.setAccessibilityLabel(label)
        updateHoverTimer()
        settingsController?.refresh()
    }

    private func scheduleCollapse() {
        collapseTimer?.invalidate()
        guard autoCollapseSeconds > 0, !isCollapsed, !isArranging, !isMenuOpen,
              settingsController?.window?.isVisible != true else { return }
        collapseTimer = Timer.scheduledTimer(timeInterval: TimeInterval(autoCollapseSeconds),
            target: self, selector: #selector(autoCollapse), userInfo: nil, repeats: false)
    }

    @objc private func autoCollapse() {
        let mouse = NSEvent.mouseLocation
        let isUsingMenuBar = NSScreen.screens.contains { screen in
            screen.frame.contains(mouse) && mouse.y >= screen.frame.maxY - 36
        }
        if isUsingMenuBar || NSEvent.pressedMouseButtons != 0 {
            scheduleCollapse()
            return
        }
        setCollapsed(true)
    }

    @objc private func screenChanged() {
        // Reveal after a display change so the user can recover any displaced control.
        isArranging = true
        setCollapsed(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.isArranging = false
            self?.scheduleCollapse()
        }
    }

    @objc private func quitApp() {
        setCollapsed(false)
        NSApp.terminate(nil)
    }
}
