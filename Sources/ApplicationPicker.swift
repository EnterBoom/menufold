import AppKit

@MainActor
final class ApplicationPicker: NSWindowController {
    private var choices: [(button: NSButton, bundle: String, name: String)] = []

    var selectedApplications: [String: String] {
        Dictionary(uniqueKeysWithValues: choices.filter { $0.button.state == .on }.map { ($0.bundle, $0.name) })
    }

    init(selected: [String: String]) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 486),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "选择收纳应用"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        guard let content = window.contentView else { return }

        let title = NSTextField(labelWithString: "勾选要收纳菜单栏图标的应用")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.frame = NSRect(x: 24, y: 436, width: 392, height: 24)
        content.addSubview(title)
        let description = NSTextField(wrappingLabelWithString: "按应用图标和名称勾选。应用图标可能与顶部菜单栏的符号不同。")
        description.font = .systemFont(ofSize: 12)
        description.textColor = .secondaryLabelColor
        description.frame = NSRect(x: 24, y: 400, width: 392, height: 32)
        content.addSubview(description)

        let excluded = Set(["local.vanya.MenuFold", "com.apple.controlcenter", "com.apple.systemuiserver",
            "com.apple.finder", "com.apple.loginwindow", "com.apple.dock"])
        var applications = selected
        var applicationURLs: [String: URL] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let bundle = app.bundleIdentifier, !excluded.contains(bundle),
                  !bundle.hasPrefix("com.apple."), app.activationPolicy != .prohibited,
                  app.bundleURL?.pathExtension == "app" else { continue }
            applications[bundle] = app.localizedName ?? bundle
            applicationURLs[bundle] = app.bundleURL
        }

        let scroll = NSScrollView(frame: NSRect(x: 24, y: 68, width: 392, height: 320))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let document = FlippedView(frame: NSRect(x: 0, y: 0, width: 372,
            height: max(320, CGFloat(applications.count) * 44 + 16)))
        for (index, item) in applications.sorted(by: { $0.value.localizedStandardCompare($1.value) == .orderedAscending }).enumerated() {
            let checkbox = ApplicationChoiceButton(frame: NSRect(x: 12, y: CGFloat(index) * 44 + 8, width: 348, height: 40))
            checkbox.setButtonType(.switch)
            checkbox.title = ""
            checkbox.setAccessibilityLabel(item.value)
            checkbox.state = selected[item.key] == nil ? .off : .on
            let iconView = NSImageView(frame: NSRect(x: 28, y: 6, width: 28, height: 28))
            let applicationURL = applicationURLs[item.key] ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.key)
            iconView.image = applicationURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
                ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            iconView.imageScaling = .scaleProportionallyUpOrDown
            iconView.setAccessibilityElement(false)
            checkbox.addSubview(iconView)
            let name = NSTextField(labelWithString: item.value)
            name.frame = NSRect(x: 66, y: 11, width: 280, height: 18)
            name.lineBreakMode = .byTruncatingTail
            name.setAccessibilityElement(false)
            checkbox.addSubview(name)
            document.addSubview(checkbox)
            choices.append((checkbox, item.key, item.value))
        }
        scroll.documentView = document
        content.addSubview(scroll)

        let cancel = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.frame = NSRect(x: 230, y: 20, width: 80, height: 32)
        content.addSubview(cancel)
        let save = NSButton(title: "保存选择", target: self, action: #selector(save))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.frame = NSRect(x: 314, y: 20, width: 104, height: 32)
        content.addSubview(save)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func save() { if let window { window.sheetParent?.endSheet(window, returnCode: .OK) } }
    @objc private func cancel() { if let window { window.sheetParent?.endSheet(window, returnCode: .cancel) } }
}

private final class ApplicationChoiceButton: NSButton {
    // Clicks on the icon and label toggle the same native checkbox as the row.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
