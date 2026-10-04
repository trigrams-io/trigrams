import AppKit
import SwiftUI

/// Block-level layout supplements SwiftUI's inline Markdown support while
/// keeping every paragraph, code block, and table cell selectable.
struct MarkdownView: View {
    let text: String
    @Environment(\.nanoPalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case .code(let language, let text):
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            if !language.isEmpty { Text(language).font(TrigramsFont.body(12)).foregroundStyle(palette.secondary) }
                            Spacer()
                            IconButton(icon: .copy, label: String(localized: "Copy code"), identifier: "copyCodeButton.\(index)") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                            }
                        }
                        ScrollView(.horizontal) {
                            Text(text).font(TrigramsFont.code()).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.scrollIndicators(.hidden)
                    }
                    .padding(12).background(palette.highlight, in: RoundedRectangle(cornerRadius: 8))
                case .heading(let level, let text):
                    inline(text).font(TrigramsFont.medium(level == 1 ? 23 : level == 2 ? 19 : 16)).foregroundStyle(palette.strong)
                case .table(let rows):
                    ScrollView(.horizontal) {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                                GridRow {
                                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                        inline(cell).font(rowIndex == 0 ? TrigramsFont.medium(14) : TrigramsFont.body(14)).padding(.vertical, 3)
                                    }
                                }
                            }
                        }.padding(12)
                    }
                    .scrollIndicators(.hidden).background(palette.highlight, in: RoundedRectangle(cornerRadius: 8))
                case .paragraph(let text):
                    inline(text).font(TrigramsFont.body(15)).lineSpacing(6)
                }
            }
        }
        .foregroundStyle(palette.foreground)
        .tint(palette.accentText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ value: String) -> some View {
        let attributed = try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        return Text(attributed ?? AttributedString(value)).textSelection(.enabled)
    }

    private enum Block { case paragraph(String), heading(Int, String), code(String, String), table([[String]]) }
    private var blocks: [Block] {
        let lines = text.components(separatedBy: "\n")
        var result: [Block] = []
        var paragraph: [String] = []
        var index = 0
        func flush() {
            if !paragraph.isEmpty { result.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("```") {
                flush()
                let language = String(line.dropFirst(3))
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].hasPrefix("```") { code.append(lines[index]); index += 1 }
                result.append(.code(language, code.joined(separator: "\n")))
            } else if line.hasPrefix("#"), let space = line.firstIndex(of: " "), line[..<space].allSatisfy({ $0 == "#" }) {
                flush()
                result.append(.heading(line.distance(from: line.startIndex, to: space), String(line[line.index(after: space)...])))
            } else if line.contains("|"), index + 1 < lines.count, isTableRule(lines[index + 1]) {
                flush()
                var rows = [cells(line)]
                index += 2
                while index < lines.count, lines[index].contains("|"), !lines[index].isEmpty { rows.append(cells(lines[index])); index += 1 }
                result.append(.table(rows))
                continue
            } else if line.isEmpty { flush() }
            else { paragraph.append(line) }
            index += 1
        }
        flush()
        return result.isEmpty ? [.paragraph(text)] : result
    }
    private func cells(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    private func isTableRule(_ line: String) -> Bool {
        line.contains("-") && line.allSatisfy { "|:- \t".contains($0) }
    }
}
