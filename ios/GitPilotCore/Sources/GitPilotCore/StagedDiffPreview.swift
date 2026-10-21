import Foundation

/// A bounded line diff for reviewing staged changes before a real Git commit.
/// Large inputs avoid an expensive full diff and show an explicit fallback.
public enum StagedDiffPreview {
    public enum Kind: String { case added, removed, unchanged, warning }
    public struct Line: Identifiable {
        public let id: Int
        public let kind: Kind
        public let text: String
        public var prefix: String {
            switch kind { case .added: return "+"; case .removed: return "−"; case .unchanged: return " "; case .warning: return "!" }
        }
    }

    public static func lines(from before: String, to after: String, maxLines: Int = 140) -> [Line] {
        guard maxLines >= 2 && maxLines <= 500 else {
            return [Line(id: 0, kind: .warning, text: "Invalid diff preview size.")]
        }
        let old = before.components(separatedBy: "\n")
        let new = after.components(separatedBy: "\n")
        func numbered(_ items: [(Kind, String)]) -> [Line] {
            items.enumerated().map { Line(id: $0.offset, kind: $0.element.0, text: $0.element.1) }
        }
        guard old.count <= 1_200, new.count <= 1_200 else {
            return numbered([(.warning, "File too large for an inline diff. The original blob SHA is still checked before commit.")])
        }
        let diff = new.difference(from: old)
        var removed = Set<Int>(), added = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): added.insert(offset)
            }
        }
        var result: [(Kind, String)] = []
        var i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count && removed.contains(i) {
                result.append((.removed, old[i])); i += 1
            } else if j < new.count && added.contains(j) {
                result.append((.added, new[j])); j += 1
            } else if i < old.count && j < new.count {
                result.append((.unchanged, old[i])); i += 1; j += 1
            } else {
                // Fail visibly if a future collection-difference algorithm changes.
                return numbered([(.warning, "Diff preview unavailable; review the complete file before committing.")])
            }
        }
        if result.count <= maxLines { return numbered(result) }
        // Preserve changes preferentially; omit large unchanged stretches.
        let changed = result.enumerated().filter { $0.element.0 != .unchanged }.map(\.offset)
        if changed.count > maxLines {
            return numbered(Array(result.filter { $0.0 != .unchanged }.prefix(maxLines - 1)) +
                            [(.warning, "Further changes omitted from preview.")])
        }
        let context = Set(changed.flatMap { idx in (max(0, idx - 2)...min(result.count - 1, idx + 2)) })
        var selected: [(Kind, String)] = []
        var skipped = false
        for (index, entry) in result.enumerated() {
            if context.contains(index) {
                if skipped { selected.append((.warning, "… unchanged lines omitted …")); skipped = false }
                selected.append(entry)
            } else { skipped = true }
            if selected.count >= maxLines - 1 { break }
        }
        if skipped { selected.append((.warning, "… remaining lines omitted …")) }
        return numbered(selected)
    }
}
