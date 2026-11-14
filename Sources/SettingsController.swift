import AppKit

@MainActor
final class SettingsController: NSWindowController, NSWindowDelegate {
    private unowned let app: AppDelegate
    private let stateLabel = NSTextField(labelWithString: "")
    private let toggleButton = NSButton()
    private let autoCollapse = NSPopUpButton()
    private let startCollapsed = NSButton(checkboxWithTitle: "启动后自动收起", target: nil, action: nil)
    private let login = NSButton(checkboxWithTitle: "登录 Mac 时启动", target: nil, action: nil)
    private let hover = NSButton(checkboxWithTitle: "鼠标悬停顶部“收纳”时展开", target: nil, action: nil)
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let selectionLabel = NSTextField(labelWithString: "")
    private var picker: ApplicationPicker?
    private let spacing = MenuBarSpacing()
    private let spacingPicker = NSPopUpButton()
    private let spacingCurrent = NSTextField(labelWithString: "")
    private let spacingFeedback = NSTextField(wrappingLabelWithString: "")
    private let applySpacingButton = NSButton()
    private let restoreSpacingButton = NSButton()

    init(app: AppDelegate) {
        self.app = app
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 780),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "折叠菜单栏"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.setFrameAutosaveName("MenuFold.Settings")
        super.init(window: window)
        window.delegate = self
        buildContent()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        refresh()
        refreshSpacingSelection()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) { app.settingsClosed() }

    func showArrangementHint() {
        hint.stringValue = "保持展开，按住 ⌘ 拖动顶部图标。整理完成后点击“收起图标”。"
    }

    func chooseApplications(collapseAfterSaving: Bool = false) {
        guard let window, picker == nil else { return }
        let picker = ApplicationPicker(selected: app.hiddenApplications)
        self.picker = picker
        guard let sheet = picker.window else { return }
        window.beginSheet(sheet) { [weak self] result in
            guard let self else { return }
            if result == .OK { self.app.hiddenApplications = picker.selectedApplications }
            self.picker = nil
            if result == .OK && collapseAfterSaving && !self.app.hiddenApplications.isEmpty {
                self.app.setCollapsed(true)
            }
        }
    }

    func refresh() {
        let needsSelection = app.usesNativeVisibility && app.hiddenApplications.isEmpty
        stateLabel.stringValue = needsSelection ? "先选择要收纳的应用" :
            (app.isUpdating ? "正在收纳…" : (app.isCollapsed ? "已请求收起图标" : "图标已展开"))
        toggleButton.title = needsSelection ? "选择收纳应用" : (app.isCollapsed ? "展开图标" : "收起图标")
        toggleButton.isEnabled = !app.isUpdating
        selectionLabel.stringValue = "已选择 \(app.hiddenApplications.count) 个应用"
        autoCollapse.selectItem(withTag: app.autoCollapseSeconds)
        startCollapsed.state = app.collapseAtLaunch ? .on : .off
        login.state = app.launchAtLogin ? .on : .off
        hover.state = app.expandOnHover ? .on : .off
        hint.textColor = app.arrangementWarning ? .systemOrange : .secondaryLabelColor
        hint.stringValue = app.statusMessage ?? (app.arrangementWarning
            ? "请按住 ⌘，把分隔线拖到箭头左侧，再试一次。"
            : (app.expandOnHover
                ? "悬停菜单栏“收纳”约半秒即可展开，也可直接点击。"
                : "点击顶部“收纳”切换展开或收起，右键打开设置。"))
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        return label
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let scroll = NSScrollView(frame: content.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let document = SettingsDocumentView(frame: content.bounds)
        scroll.documentView = document
        content.addSubview(scroll)
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 20
        root.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 32),
            root.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -32),
            root.topAnchor.constraint(equalTo: document.topAnchor, constant: 20)
        ])

        let title = label("让菜单栏清爽一点", size: 25, weight: .semibold)
        let subtitle = label("常用图标留在外面，其余一键收起。", size: 13)
        subtitle.textColor = .secondaryLabelColor
        let header = NSStackView(views: [title, subtitle])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 7
        root.addArrangedSubview(header)

        if app.usesNativeVisibility {
            selectionLabel.font = .systemFont(ofSize: 14, weight: .medium)
            let choose = NSButton(title: "选择收纳应用…", target: self, action: #selector(openPicker))
            choose.bezelStyle = .rounded
            choose.controlSize = .large
            let selection = NSStackView(views: [selectionLabel, NSView(), choose])
            root.addArrangedSubview(selection)
            selection.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
            selection.heightAnchor.constraint(equalToConstant: 92).isActive = true
        } else {
            let diagram = ArrangementView()
            root.addArrangedSubview(diagram)
            diagram.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
            diagram.heightAnchor.constraint(equalToConstant: 92).isActive = true
        }

        let instructions = NSTextField(wrappingLabelWithString:
            app.usesNativeVisibility
            ? "选择要收纳的应用，再点击“收起图标”。\n同一应用的多个图标会一起收纳，系统图标保持可见。"
            : "按住 ⌘ Command，将要收纳的图标拖到分隔线左侧。\n把常用图标留在箭头右侧。")
        instructions.font = .systemFont(ofSize: 13)
        instructions.maximumNumberOfLines = 3
        root.addArrangedSubview(instructions)
        instructions.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        stateLabel.font = .systemFont(ofSize: 13, weight: .medium)
        stateLabel.textColor = .secondaryLabelColor
        toggleButton.bezelStyle = .rounded
        toggleButton.controlSize = .large
        toggleButton.target = self
        toggleButton.action = #selector(toggle)
        toggleButton.keyEquivalent = "\r"
        toggleButton.widthAnchor.constraint(equalToConstant: 140).isActive = true
        let status = NSStackView(views: [stateLabel, NSView(), toggleButton])
        status.orientation = .horizontal
        root.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let restore = NSButton(title: "恢复顶部按钮", target: app, action: #selector(AppDelegate.restoreControlItem))
        restore.bezelStyle = .rounded
        let shortcut = label(app.hasRecoveryShortcut ? "快捷键  ⌃⌥⌘B" : "快捷键注册失败，可使用上方按钮", size: 12)
        shortcut.textColor = .secondaryLabelColor
        let recovery = NSStackView(views: [restore, NSView(), shortcut])
        root.addArrangedSubview(recovery)
        recovery.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let line = NSBox()
        line.boxType = .separator
        root.addArrangedSubview(line)
        line.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        addSpacingControls(to: root)

        let spacingLine = NSBox()
        spacingLine.boxType = .separator
        root.addArrangedSubview(spacingLine)
        spacingLine.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        for (title, seconds) in [("保持展开", 0), ("10 秒后", 10), ("30 秒后", 30), ("1 分钟后", 60)] {
            autoCollapse.addItem(withTitle: title)
            autoCollapse.lastItem?.tag = seconds
        }
        autoCollapse.target = self
        autoCollapse.action = #selector(changeAutoCollapse)
        autoCollapse.widthAnchor.constraint(equalToConstant: 140).isActive = true
        let timerRow = NSStackView(views: [label("展开后自动收起", size: 13), NSView(), autoCollapse])
        root.addArrangedSubview(timerRow)
        timerRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        startCollapsed.target = self
        startCollapsed.action = #selector(changeStartup)
        login.target = self
        login.action = #selector(changeLogin)
        hover.target = self
        hover.action = #selector(changeHover)
        let switches = NSStackView(views: [hover, startCollapsed, login])
        switches.orientation = .vertical
        switches.alignment = .leading
        switches.spacing = 12
        root.addArrangedSubview(switches)

        hint.font = .systemFont(ofSize: 12)
        hint.maximumNumberOfLines = 2
        root.addArrangedSubview(hint)
        hint.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let version = label("MenuFold 0.1.7 · 本机运行", size: 11)
        version.textColor = .tertiaryLabelColor
        root.addArrangedSubview(version)
        document.layoutSubtreeIfNeeded()
        document.setFrameSize(NSSize(width: content.bounds.width, height: root.fittingSize.height + 44))
        document.layoutSubtreeIfNeeded()
        scroll.contentView.scroll(to: .zero)
        refresh()
    }

    private func addSpacingControls(to root: NSStackView) {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 10
        root.addArrangedSubview(section)
        section.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        section.addArrangedSubview(label("第三方图标间距", size: 14, weight: .semibold))
        spacingCurrent.font = .systemFont(ofSize: 12)
        spacingCurrent.textColor = .secondaryLabelColor
        section.addArrangedSubview(spacingCurrent)

        for preset in MenuBarSpacing.presets {
            spacingPicker.addItem(withTitle: preset.title)
            spacingPicker.lastItem?.tag = preset.tag
        }
        spacingPicker.addItem(withTitle: "当前自定义配置")
        spacingPicker.lastItem?.tag = 0
        spacingPicker.target = self
        spacingPicker.action = #selector(spacingSelectionChanged)
        spacingPicker.widthAnchor.constraint(equalToConstant: 172).isActive = true
        applySpacingButton.title = "应用间距"
        applySpacingButton.bezelStyle = .rounded
        applySpacingButton.target = self
        applySpacingButton.action = #selector(applySpacing)
        restoreSpacingButton.title = "恢复调整前"
        restoreSpacingButton.bezelStyle = .rounded
        restoreSpacingButton.target = self
        restoreSpacingButton.action = #selector(restoreSpacing)
        let controls = NSStackView(views: [spacingPicker, applySpacingButton, restoreSpacingButton])
        controls.spacing = 8
        section.addArrangedSubview(controls)

        let scope = NSTextField(wrappingLabelWithString:
            "作用于本机第三方应用图标。Wi-Fi、电池、时钟和控制中心的图标间距由 macOS 管理。保存后重新打开相关应用，或重新登录后生效。")
        scope.font = .systemFont(ofSize: 12)
        scope.textColor = .secondaryLabelColor
        section.addArrangedSubview(scope)
        scope.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        spacingFeedback.font = .systemFont(ofSize: 12)
        spacingFeedback.textColor = .secondaryLabelColor
        spacingFeedback.stringValue = "首次应用时自动保存调整前配置，支持恢复原值。"
        section.addArrangedSubview(spacingFeedback)
        spacingFeedback.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        refreshSpacingSelection()
    }

    private func refreshSpacingSelection() {
        spacingCurrent.stringValue = "当前配置为\(spacing.currentDescription)"
        spacingPicker.selectItem(withTag: spacing.currentTag)
        spacingSelectionChanged()
        restoreSpacingButton.isEnabled = spacing.hasBackup
    }

    @objc private func spacingSelectionChanged() {
        applySpacingButton.isEnabled = spacingPicker.selectedTag() != 0
    }

    @objc private func applySpacing() {
        guard let preset = MenuBarSpacing.presets.first(where: { $0.tag == spacingPicker.selectedTag() }) else { return }
        do {
            try spacing.apply(preset)
            spacingFeedback.stringValue = "已保存\(preset.title)。重新打开相关应用或重新登录后生效。"
        } catch { showSpacingError(error) }
        refreshSpacingSelection()
    }

    @objc private func restoreSpacing() {
        do {
            try spacing.restoreOriginal()
            spacingFeedback.stringValue = "已恢复调整前配置。重新打开相关应用或重新登录后生效。"
        } catch { showSpacingError(error) }
        refreshSpacingSelection()
    }

    private func showSpacingError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "间距设置未完成"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    @objc private func toggle() { app.finishArranging() }
    @objc private func openPicker() { chooseApplications() }
    @objc private func changeAutoCollapse() { app.autoCollapseSeconds = autoCollapse.selectedTag() }
    @objc private func changeStartup() { app.collapseAtLaunch = startCollapsed.state == .on }
    @objc private func changeLogin() { app.setLaunchAtLogin(login.state == .on) }
    @objc private func changeHover() { app.expandOnHover = hover.state == .on }
}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class ArrangementView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        let bar = NSRect(x: 15, y: 43, width: bounds.width - 30, height: 32)
        NSColor.quaternaryLabelColor.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 7, yRadius: 7).fill()

        let dividerX = bounds.width * 0.52
        for (index, name) in ["cloud", "headphones", "square.stack"].enumerated() {
            drawSymbol(name, x: 34 + CGFloat(index) * 38, y: 51, color: .secondaryLabelColor)
        }
        NSColor.separatorColor.setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: dividerX, y: 48))
        separator.line(to: NSPoint(x: dividerX, y: 70))
        separator.lineWidth = 1.5
        separator.stroke()
        drawSymbol("chevron.right", x: dividerX + 22, y: 51, color: .controlAccentColor)
        drawSymbol("wifi", x: bounds.width - 97, y: 51, color: .labelColor)
        drawSymbol("battery.100percent", x: bounds.width - 57, y: 51, color: .labelColor)

        drawText("收纳区", x: 33, y: 16)
        drawText("分隔线", x: dividerX - 18, y: 16)
        drawText("常驻区", x: bounds.width - 104, y: 16)
    }

    private func drawSymbol(_ name: String, x: CGFloat, y: CGFloat, color: NSColor) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium)) else { return }
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceIn)
            return true
        }
        tinted.draw(in: NSRect(x: x, y: y, width: 20, height: 17))
    }

    private func drawText(_ text: String, x: CGFloat, y: CGFloat) {
        (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor
        ])
    }
}
