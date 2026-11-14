import Foundation

@MainActor
final class MenuBarSpacing {
    struct Preset {
        let tag: Int
        let title: String
        let value: Int?
    }

    static let presets = [
        Preset(tag: 4, title: "紧凑（4）", value: 4),
        Preset(tag: 8, title: "适中（8）", value: 8),
        Preset(tag: -1, title: "系统默认", value: nil),
        Preset(tag: 24, title: "宽松（24）", value: 24)
    ]

    private let keys = ["NSStatusItemSpacing", "NSStatusItemSelectionPadding"]
    private let backupURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MenuFold/spacing-original.plist")

    var hasBackup: Bool { FileManager.default.fileExists(atPath: backupURL.path) }

    var currentDescription: String {
        let values = read()
        if values.isEmpty {
            let inherited = read(host: kCFPreferencesAnyHost)
            return inherited.isEmpty ? "系统默认" : "沿用已有全局设置（\(describe(inherited))）"
        }
        if let preset = Self.presets.first(where: { matches(values, value: $0.value) }) {
            return preset.title
        }
        return "自定义（\(describe(values))）"
    }

    var currentTag: Int {
        let values = read()
        return Self.presets.first(where: { matches(values, value: $0.value) })?.tag ?? 0
    }

    func apply(_ preset: Preset) throws {
        let current = read()
        if hasBackup {
            _ = try loadBackup()
        } else {
            let snapshot: [String: Any] = ["schemaVersion": 1, "preferences": current]
            let data = try PropertyListSerialization.data(fromPropertyList: snapshot, format: .xml, options: 0)
            try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: backupURL, options: .atomic)
        }
        let values: [String: Any] = preset.value.map { value in
            Dictionary(uniqueKeysWithValues: keys.map { ($0, NSNumber(value: value)) })
        } ?? [:]
        try replace(with: values)
    }

    func restoreOriginal() throws { try replace(with: loadBackup()) }

    private func loadBackup() throws -> [String: Any] {
        let data = try Data(contentsOf: backupURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let snapshot = plist as? [String: Any], snapshot["schemaVersion"] as? Int == 1,
              let values = snapshot["preferences"] as? [String: Any],
              Set(values.keys).isSubset(of: Set(keys)) else { throw SpacingError.invalidBackup }
        return values
    }

    private func read(host: CFString = kCFPreferencesCurrentHost) -> [String: Any] {
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, host)
        var values: [String: Any] = [:]
        for key in keys {
            if let value = CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser, host) { values[key] = value }
        }
        return values
    }

    private func write(_ values: [String: Any]) -> Bool {
        let removed = keys.filter { values[$0] == nil }
        CFPreferencesSetMultiple(values as CFDictionary, removed as CFArray,
            kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        return CFPreferencesSynchronize(kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    private func replace(with values: [String: Any]) throws {
        let previous = read()
        if write(values) && NSDictionary(dictionary: read()).isEqual(to: values) { return }
        let restored = write(previous) && NSDictionary(dictionary: read()).isEqual(to: previous)
        throw restored ? SpacingError.writeFailed : SpacingError.rollbackFailed
    }

    private func matches(_ values: [String: Any], value: Int?) -> Bool {
        guard let value else { return values.isEmpty }
        return keys.allSatisfy { key in
            if let number = values[key] as? NSNumber { return number.doubleValue == Double(value) }
            if let string = values[key] as? String { return Double(string) == Double(value) }
            return false
        }
    }

    private func describe(_ values: [String: Any]) -> String {
        keys.map { values[$0].map { String(describing: $0) } ?? "默认" }.joined(separator: " / ")
    }

    private enum SpacingError: LocalizedError {
        case invalidBackup, writeFailed, rollbackFailed

        var errorDescription: String? {
            switch self {
            case .invalidBackup: return "原始间距备份无法读取，当前设置尚未更改。"
            case .writeFailed: return "间距设置保存失败，已恢复本次操作前的配置。"
            case .rollbackFailed: return "间距配置保存和自动恢复均未通过验证，请检查系统偏好设置的写入权限。"
            }
        }
    }
}
