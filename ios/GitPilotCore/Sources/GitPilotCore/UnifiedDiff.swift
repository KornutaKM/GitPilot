import Foundation

/// Parses @@ -old,count +new,count @@ hunks into file-relative line numbers.
/// Review comments must target LEFT deletions or RIGHT additions/context, not hunk headers.
struct DiffLine: Identifiable, Equatable {
    enum Kind: Equatable { case header, context, addition, deletion, annotation }
    let id: Int
    let text: String
    let kind: Kind
    let oldLine: Int?
    let newLine: Int?
    var reviewLocation: (line: Int, side: String)? {
        switch kind {
        case .addition, .context: return newLine.map { ($0, "RIGHT") }
        case .deletion: return oldLine.map { ($0, "LEFT") }
        default: return nil
        }
    }
}

enum UnifiedDiff {
    static func parse(_ patch: String) -> [DiffLine] {
        var oldLine = 0
        var newLine = 0
        var inHunk = false
        var result: [DiffLine] = []
        let pattern = #"^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
        let regex = try! NSRegularExpression(pattern: pattern)
        for (index, row) in patch.components(separatedBy: "\n").enumerated() {
            let nsRange = NSRange(row.startIndex..<row.endIndex, in: row)
            if let match = regex.firstMatch(in: row, range: nsRange),
               let oldRange = Range(match.range(at: 1), in: row),
               let newRange = Range(match.range(at: 2), in: row),
               let o = Int(row[oldRange]), let n = Int(row[newRange]) {
                oldLine = o; newLine = n; inHunk = true
                result.append(DiffLine(id: index, text: row, kind: .header, oldLine: nil, newLine: nil))
            } else if inHunk && row.hasPrefix("+") {
                result.append(DiffLine(id: index, text: row, kind: .addition, oldLine: nil, newLine: newLine))
                newLine += 1
            } else if inHunk && row.hasPrefix("-") {
                result.append(DiffLine(id: index, text: row, kind: .deletion, oldLine: oldLine, newLine: nil))
                oldLine += 1
            } else if inHunk && row.hasPrefix(" ") {
                result.append(DiffLine(id: index, text: row, kind: .context, oldLine: oldLine, newLine: newLine))
                oldLine += 1; newLine += 1
            } else {
                result.append(DiffLine(id: index, text: row, kind: .annotation, oldLine: nil, newLine: nil))
            }
        }
        return result
    }
}
