import AppKit

/// 長按面板的內容：把分群平衡分配到 1–3 欄，欄寬固定，內容多寡只影響高度。
final class OverlayColumnsView: NSView {
    private static let columnWidth: CGFloat = 260
    private static let columnSpacing: CGFloat = 28
    private static let padding: CGFloat = 20
    /// 每個分類最多顯示這麼多條，超過的用「…還有 N 條」收尾——不然單一分類塞了
    /// 幾十條熱鍵時，面板會直接長到螢幕外面去，而且完全沒有東西可以捲動看到它們
    /// （面板是 ignoresMouseEvents，本來就不能互動，加捲軸也沒用）。
    private static let maxEntriesPerGroup = 10

    init(groups: [HotkeyGroup]) {
        super.init(frame: .zero)

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        effect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effect)
        NSLayoutConstraint.activate([
            effect.topAnchor.constraint(equalTo: topAnchor),
            effect.leadingAnchor.constraint(equalTo: leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: trailingAnchor),
            effect.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let columnStacks = Self.balancedColumns(for: groups).map { columnGroups -> NSStackView in
            let stack = NSStackView(views: columnGroups.map(Self.makeGroupView))
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 16
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.widthAnchor.constraint(equalToConstant: Self.columnWidth).isActive = true
            return stack
        }

        let rowStack = NSStackView(views: columnStacks)
        rowStack.orientation = .horizontal
        rowStack.alignment = .top
        rowStack.spacing = Self.columnSpacing
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: effect.topAnchor, constant: Self.padding),
            rowStack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: Self.padding),
            rowStack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -Self.padding),
            rowStack.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -Self.padding)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 把分群依「entry 數＋1（標題）」當重量，貪心塞進目前最輕的那一欄，欄數依總分群數決定。
    ///
    /// 上限固定在 3 欄，不是隨便選的：`OverlayWindowController` 把面板寬度封頂在 900pt，
    /// 而 3 欄（3×260 ＋ 2×28 ＋ 2×20 ＝ 876pt）剛好卡在這個上限之內，4 欄會需要 1164pt。
    /// NSPanel 不會把自己縮到比 Auto Layout 要求的最小尺寸更小，超過上限的話面板會
    /// 悄悄長回實際內容寬度、位置卻還是照小尺寸算的，整個面板會偏離螢幕中心。
    private static func balancedColumns(for groups: [HotkeyGroup]) -> [[HotkeyGroup]] {
        let columnCount: Int
        switch groups.count {
        case 0...1: columnCount = 1
        case 2...4: columnCount = 2
        default: columnCount = 3
        }

        var columns: [[HotkeyGroup]] = Array(repeating: [], count: columnCount)
        var weights = Array(repeating: 0, count: columnCount)

        for group in groups {
            let lightest = weights.indices.min { weights[$0] < weights[$1] } ?? 0
            columns[lightest].append(group)
            weights[lightest] += group.entries.count + 1
        }
        return columns.filter { !$0.isEmpty }
    }

    /// 分類標題的強調色。原本標題、熱鍵、說明都用同一組白／灰，掃讀時很難一眼分出
    /// 「這是分類」還是「這是熱鍵」，所以三層各給一種辨識方式：標題上色＋分隔線、
    /// 熱鍵套鍵帽底色、說明維持次要灰。這裡刻意不用 controlAccentColor——強調色可以
    /// 被使用者設成石墨灰，那就等於沒上色，白字問題照樣存在。
    private static let headerColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.45, green: 0.80, blue: 1.00, alpha: 1)
            : NSColor(srgbRed: 0.00, green: 0.32, blue: 0.60, alpha: 1)
    }

    private static func makeGroupView(_ group: HotkeyGroup) -> NSView {
        let header = NSTextField(labelWithString: group.name)
        header.font = .systemFont(ofSize: 13.5, weight: .heavy)
        header.textColor = headerColor

        // NSBox 的 separator 自己會跟著亮暗外觀換色，不必自己管 layer 顏色。
        let rule = NSBox()
        rule.boxType = .separator
        rule.translatesAutoresizingMaskIntoConstraints = false
        rule.widthAnchor.constraint(equalToConstant: columnWidth).isActive = true

        let headerStack = NSStackView(views: [header, rule])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 5

        var entryViews = group.entries.prefix(maxEntriesPerGroup).map(makeEntryView)
        let hiddenCount = group.entries.count - entryViews.count
        if hiddenCount > 0 {
            let more = NSTextField(labelWithString: "…還有 \(hiddenCount) 條")
            more.font = .systemFont(ofSize: 11)
            more.textColor = .tertiaryLabelColor
            entryViews.append(more)
        }

        let entriesStack = NSStackView(views: entryViews)
        entriesStack.orientation = .vertical
        entriesStack.alignment = .leading
        entriesStack.spacing = 8

        let stack = NSStackView(views: [headerStack, entriesStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }

    private static func makeEntryView(_ entry: HotkeyEntry) -> NSView {
        let keyCap = KeyCapView(text: entry.keys)

        let descriptionLabel = NSTextField(wrappingLabelWithString: entry.description)
        descriptionLabel.font = .systemFont(ofSize: 11.5)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.preferredMaxLayoutWidth = columnWidth
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.widthAnchor.constraint(lessThanOrEqualToConstant: columnWidth).isActive = true

        let stack = NSStackView(views: entry.description.isEmpty ? [keyCap] : [keyCap, descriptionLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        return stack
    }
}

/// 一顆鍵帽：熱鍵字串加上圓角底色與外框，讓它跟上面的分類標題、下面的說明文字
/// 一眼就分得開。底色用 labelColor 疊透明度而不是寫死的白／黑，才能同時吃亮暗外觀；
/// 但 CALayer 不會自動重算動態顏色，所以外觀變更時要自己再套一次。
private final class KeyCapView: NSView {
    init(text: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1

        let label = NSTextField(labelWithString: text)
        label.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7)
        ])

        applyLayerColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyLayerColors()
    }

    private func applyLayerColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.14).cgColor
            layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.24).cgColor
        }
    }
}
