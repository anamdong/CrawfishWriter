import SwiftUI
import WebKit
import AppKit

struct MarkdownWebPreviewView: NSViewRepresentable {
    let markdown: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = false
        configureOverlayScrollbars(for: webView)
        DispatchQueue.main.async {
            configureOverlayScrollbars(for: webView)
        }
        webView.loadHTMLString(MarkdownWebRenderer.htmlDocument(from: markdown), baseURL: nil)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        configureOverlayScrollbars(for: nsView)
        context.coordinator.render(markdown: markdown, in: nsView)
    }

    private func configureOverlayScrollbars(for webView: WKWebView) {
        guard let scrollView = firstScrollView(in: webView) else { return }
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScroller?.controlSize = .small
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }

        for subview in view.subviews {
            if let found = firstScrollView(in: subview) {
                return found
            }
        }

        return nil
    }

    final class Coordinator {
        private var lastMarkdown: String = ""

        func render(markdown: String, in webView: WKWebView) {
            guard markdown != lastMarkdown else { return }
            lastMarkdown = markdown
            webView.loadHTMLString(MarkdownWebRenderer.htmlDocument(from: markdown), baseURL: nil)
        }
    }
}

enum MarkdownWebRenderer {
    private enum ListType {
        case unordered
        case ordered

        var tagName: String {
            switch self {
            case .unordered:
                return "ul"
            case .ordered:
                return "ol"
            }
        }
    }

    private struct ListContext {
        var type: ListType
        var indent: Int
        var hasOpenListItem: Bool
    }

    static func htmlDocument(from markdown: String) -> String {
        let bodyHTML = makeHTMLBody(from: markdown)
        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <style>
            :root {
              color-scheme: light dark;
              --bg: #ffffff;
              --fg: #1d1d1f;
              --muted: #5c5f66;
              --rule: #d9dade;
              --code-bg: #f5f6f8;
              --link: #3b6ea9;
            }
            @media (prefers-color-scheme: dark) {
              :root {
                --bg: #111214;
                --fg: #e8e9ed;
                --muted: #a0a4ad;
                --rule: #2b2f36;
                --code-bg: #1a1d22;
                --link: #8eb7eb;
              }
            }
            html, body {
              margin: 0;
              padding: 0;
              background: var(--bg);
              color: var(--fg);
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
              line-height: 1.65;
            }
            .wrap {
              max-width: 760px;
              margin: 0 auto;
              padding: 42px 38px 92px;
              box-sizing: border-box;
            }
            ul, ol {
              margin: 0.8em 0 0.8em 1.4em;
              padding: 0;
            }
            li {
              margin: 0.2em 0;
            }
            h1, h2, h3, h4, h5, h6 {
              line-height: 1.28;
              margin-top: 1.3em;
              margin-bottom: 0.45em;
              letter-spacing: 0;
              overflow: visible;
            }
            p, ul, ol, blockquote, pre {
              margin: 0.85em 0;
            }
            hr {
              border: none;
              border-top: 1px solid var(--rule);
              margin: 1.6em 0;
            }
            a { color: var(--link); text-decoration: none; }
            a:hover { text-decoration: underline; }
            img {
              max-width: 100%;
              height: auto;
              border-radius: 10px;
              display: block;
              margin: 0.7em 0;
            }
            blockquote {
              border-left: 3px solid var(--rule);
              margin-left: 0;
              padding-left: 0.9em;
              color: var(--muted);
            }
            code, pre {
              font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
              font-size: 0.92em;
            }
            code {
              background: var(--code-bg);
              border-radius: 6px;
              padding: 0.08em 0.35em;
            }
            pre {
              background: var(--code-bg);
              border-radius: 10px;
              padding: 0.85em 1em;
              overflow-x: auto;
            }
            pre code {
              background: transparent;
              padding: 0;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              margin: 1em 0;
            }
            th, td {
              border: 1px solid var(--rule);
              padding: 0.5em 0.65em;
              text-align: left;
            }
          </style>
        </head>
        <body>
          <main class="wrap">\(bodyHTML)</main>
        </body>
        </html>
        """
    }

    private static func makeHTMLBody(from markdown: String) -> String {
        guard !markdown.isEmpty else {
            return "<p></p>"
        }

        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var htmlParts: [String] = []
        var paragraphBuffer: [String] = []
        var listStack: [ListContext] = []
        var index = 0

        func closeCurrentListItemIfNeeded() {
            guard !listStack.isEmpty else { return }
            if listStack[listStack.count - 1].hasOpenListItem {
                htmlParts.append("</li>")
                listStack[listStack.count - 1].hasOpenListItem = false
            }
        }

        func openList(_ type: ListType, indent: Int) {
            htmlParts.append("<\(type.tagName)>")
            listStack.append(ListContext(type: type, indent: indent, hasOpenListItem: false))
        }

        func closeTopList() {
            guard !listStack.isEmpty else { return }
            closeCurrentListItemIfNeeded()
            let closed = listStack.removeLast()
            htmlParts.append("</\(closed.type.tagName)>")
        }

        func closeLists(downToLessThan indent: Int) {
            while let top = listStack.last, top.indent >= indent {
                closeTopList()
            }
        }

        func closeAllLists() {
            while !listStack.isEmpty {
                closeTopList()
            }
        }

        func flushParagraphIfNeeded() {
            guard !paragraphBuffer.isEmpty else { return }
            let inline = paragraphBuffer.map(parseInline).joined(separator: "<br/>")
            htmlParts.append("<p>\(inline)</p>")
            paragraphBuffer.removeAll(keepingCapacity: true)
        }

        func appendListItem(type: ListType, indent: Int, text: String) {
            while let top = listStack.last, indent < top.indent {
                closeTopList()
            }

            if let top = listStack.last {
                if indent > top.indent {
                    openList(type, indent: indent)
                } else if indent == top.indent {
                    if top.type == type {
                        closeCurrentListItemIfNeeded()
                    } else {
                        closeTopList()
                        if listStack.isEmpty || indent > (listStack.last?.indent ?? -1) {
                            openList(type, indent: indent)
                        } else {
                            while let sibling = listStack.last,
                                  sibling.indent == indent,
                                  sibling.type != type {
                                closeTopList()
                            }
                            if listStack.last?.indent != indent || listStack.last?.type != type {
                                openList(type, indent: indent)
                            }
                        }
                    }
                }
            } else {
                openList(type, indent: indent)
            }

            if listStack.last?.indent != indent || listStack.last?.type != type {
                openList(type, indent: indent)
            }

            htmlParts.append("<li>\(parseInline(text))")
            listStack[listStack.count - 1].hasOpenListItem = true
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let fence = captureGroups(in: line, pattern: #"^\s*```([A-Za-z0-9_-]+)?\s*$"#) {
                flushParagraphIfNeeded()
                closeAllLists()

                let language = (fence.count > 1 ? fence[1] : "").trimmingCharacters(in: .whitespacesAndNewlines)
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let current = lines[index]
                    if current.range(of: #"^\s*```\s*$"#, options: .regularExpression) != nil {
                        break
                    }
                    codeLines.append(current)
                    index += 1
                }
                let code = escapeHTML(codeLines.joined(separator: "\n"))
                let classAttribute = language.isEmpty ? "" : " class=\"language-\(escapeHTML(language))\""
                htmlParts.append("<pre><code\(classAttribute)>\(code)</code></pre>")
                if index < lines.count {
                    index += 1
                }
                continue
            }

            if trimmed.isEmpty {
                flushParagraphIfNeeded()
                closeAllLists()
                index += 1
                continue
            }

            if let heading = captureGroups(in: line, pattern: #"^(#{1,6})\s+(.+?)\s*$"#) {
                flushParagraphIfNeeded()
                closeAllLists()
                let level = heading[1].count
                let content = parseInline(heading[2])
                htmlParts.append("<h\(level)>\(content)</h\(level)>")
                index += 1
                continue
            }

            if line.range(of: #"^\s*>\s?.*$"#, options: .regularExpression) != nil {
                flushParagraphIfNeeded()
                closeAllLists()

                var quoteLines: [String] = []
                while index < lines.count,
                      lines[index].range(of: #"^\s*>\s?.*$"#, options: .regularExpression) != nil {
                    let stripped = replaceFirst(
                        in: lines[index],
                        pattern: #"^\s*>\s?"#,
                        with: ""
                    )
                    quoteLines.append(parseInline(stripped))
                    index += 1
                }

                htmlParts.append("<blockquote><p>\(quoteLines.joined(separator: "<br/>"))</p></blockquote>")
                continue
            }

            if let unordered = captureGroups(in: line, pattern: #"^([ \t]*)([-+*])\s+(.+)$"#) {
                flushParagraphIfNeeded()
                let indent = indentationWidth(unordered[1])
                appendListItem(type: .unordered, indent: indent, text: unordered[3])
                index += 1
                continue
            }

            if let ordered = captureGroups(in: line, pattern: #"^([ \t]*)(\d+)\.\s+(.+)$"#) {
                flushParagraphIfNeeded()
                let indent = indentationWidth(ordered[1])
                appendListItem(type: .ordered, indent: indent, text: ordered[3])
                index += 1
                continue
            }

            closeAllLists()
            paragraphBuffer.append(trimmed)
            index += 1
        }

        flushParagraphIfNeeded()
        closeAllLists()
        return htmlParts.joined(separator: "\n")
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func parseInline(_ text: String) -> String {
        var working = text
        var codeSnippets: [String] = []

        working = replacingMatches(in: working, pattern: #"`([^`]+)`"#) { match, ns in
            let codeText = ns.substring(with: match.range(at: 1))
            let token = "__CODETOKEN_\(codeSnippets.count)__"
            codeSnippets.append("<code>\(escapeHTML(codeText))</code>")
            return token
        }

        working = escapeHTML(working)

        working = replacingMatches(in: working, pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#) { match, ns in
            let alt = ns.substring(with: match.range(at: 1))
            let rawURL = ns.substring(with: match.range(at: 2))
            let url = cleanURL(rawURL)
            return "<img src=\"\(escapeHTML(url))\" alt=\"\(escapeHTML(alt))\" />"
        }

        working = replacingMatches(in: working, pattern: #"(?<!!)\[([^\]]+)\]\(([^)]+)\)"#) { match, ns in
            let label = ns.substring(with: match.range(at: 1))
            let rawURL = ns.substring(with: match.range(at: 2))
            let url = cleanURL(rawURL)
            return "<a href=\"\(escapeHTML(url))\">\(label)</a>"
        }

        working = replacingMatches(in: working, pattern: #"\*\*\*([^*]+?)\*\*\*"#) { match, ns in
            "<strong><em>\(ns.substring(with: match.range(at: 1)))</em></strong>"
        }
        working = replacingMatches(in: working, pattern: #"___([^_]+?)___"#) { match, ns in
            "<strong><em>\(ns.substring(with: match.range(at: 1)))</em></strong>"
        }
        working = replacingMatches(in: working, pattern: #"\*\*([^*]+?)\*\*"#) { match, ns in
            "<strong>\(ns.substring(with: match.range(at: 1)))</strong>"
        }
        working = replacingMatches(in: working, pattern: #"__([^_]+?)__"#) { match, ns in
            "<strong>\(ns.substring(with: match.range(at: 1)))</strong>"
        }
        working = replacingMatches(in: working, pattern: #"(?<!\*)\*([^*]+?)\*(?!\*)"#) { match, ns in
            "<em>\(ns.substring(with: match.range(at: 1)))</em>"
        }
        working = replacingMatches(in: working, pattern: #"(?<!_)_([^_]+?)_(?!_)"#) { match, ns in
            "<em>\(ns.substring(with: match.range(at: 1)))</em>"
        }

        for (index, snippet) in codeSnippets.enumerated() {
            working = working.replacingOccurrences(of: "__CODETOKEN_\(index)__", with: snippet)
        }

        return working
    }

    private static func replacingMatches(
        in input: String,
        pattern: String,
        options: NSRegularExpression.Options = [],
        transform: (NSTextCheckingResult, NSString) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return input
        }

        let nsInput = input as NSString
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: nsInput.length))
        guard !matches.isEmpty else { return input }

        var output = ""
        var cursor = 0

        for match in matches {
            let matchStart = match.range.location
            if matchStart > cursor {
                output += nsInput.substring(with: NSRange(location: cursor, length: matchStart - cursor))
            }
            output += transform(match, nsInput)
            cursor = match.range.location + match.range.length
        }

        if cursor < nsInput.length {
            output += nsInput.substring(with: NSRange(location: cursor, length: nsInput.length - cursor))
        }

        return output
    }

    private static func captureGroups(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else {
            return nil
        }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound else { return "" }
            return nsText.substring(with: range)
        }
    }

    private static func replaceFirst(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    private static func indentationWidth(_ leadingWhitespace: String) -> Int {
        leadingWhitespace.reduce(into: 0) { width, character in
            if character == "\t" {
                width += 4
            } else {
                width += 1
            }
        }
    }

    private static func cleanURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstPart = trimmed.split(separator: " ").first {
            return String(firstPart)
        }
        return trimmed
    }
}
