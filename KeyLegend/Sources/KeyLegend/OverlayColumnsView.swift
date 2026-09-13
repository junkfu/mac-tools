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

    private static func makeGroupView(_ group: HotkeyGroup) -> NSView {
        let header = NSTextField(labelWithString: group.name)
        header.font = .boldSystemFont(ofSize: 13)
        header.textColor = .labelColor

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

        let stack = NSStackView(views: [header, entriesStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        return stack
    }

    private static func makeEntryView(_ entry: HotkeyEntry) -> NSView {
        let keysLabel = NSTextField(labelWithString: entry.keys)
        keysLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        keysLabel.textColor = .labelColor

        let descriptionLabel = NSTextField(wrappingLabelWithString: entry.description)
        descriptionLabel.font = .systemFont(ofSize: 11.5)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.preferredMaxLayoutWidth = columnWidth
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.widthAnchor.constraint(lessThanOrEqualToConstant: columnWidth).isActive = true

        let stack = NSStackView(views: entry.description.isEmpty ? [keysLabel] : [keysLabel, descriptionLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        return stack
    }
}
