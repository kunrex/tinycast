import AppKit
import SwiftUI

@main
@MainActor
struct ChatMarkdownTests {
    static func render(_ text: String, midStream: Bool = false) -> ChatRenderedText {
        ChatMarkdownRenderer(
            ChatMarkdownSource(
                blocks: MarkdownBlock.parse(text, midStream: midStream),
                metrics: .standard)
        ).render()
    }

    static func main() {
        let markdown = """
            # Heading

            A [guide](https://example.com) and **bold** text.

            - First
              - Nested

            3. Numbered

            > Quoted

            ```swift
            let apple = 1
            ```

            | Fruit | Count |
            | - | - |
            | Apple | 2 |
            """
        let drawn = render(markdown)
        let text = drawn.string.string
        precondition(text.hasPrefix("Heading\n"))
        precondition(text.contains("A guide and bold text."))
        precondition(!text.contains("[1]"), "Quick Action links have no conversation citation markers")
        precondition(text.contains("•\tFirst\n•\tNested"))
        precondition(text.contains("3.\tNumbered"))
        precondition(text.contains("Quoted") && text.contains("Apple"))
        precondition(!text.hasSuffix("\n"))
        precondition(drawn.codeBlocks.map(\.code) == ["let apple = 1"])
        precondition(drawn.codeBlocks.first?.language == "swift")

        let links = render(
            "[web](https://example.com) [mail](mailto:a@example.com) "
                + "[file](file:///Applications/Calculator.app) [app](tinycast://search)").string
        var targets: [String] = []
        links.enumerateAttribute(.link, in: NSRange(location: 0, length: links.length)) { value, _, _ in
            if let url = value as? URL { targets.append(url.absoluteString) }
        }
        precondition(targets == ["https://example.com", "mailto:a@example.com"])

        let math = render(#"Roots \(x^2\) and $y$."# + "\n\n" + #"$$\frac{a}{b}$$"#).string
        var sources: [String] = []
        math.enumerateAttribute(
            ChatMarkdownRenderer.mathSource, in: NSRange(location: 0, length: math.length)
        ) { value, range, _ in
            guard let source = value as? String else { return }
            precondition(range.length == 1)
            sources.append(source)
        }
        precondition(sources == [#"\(x^2\)"#, "$y$", #"$$\frac{a}{b}$$"#])
        precondition(render("At $5 or $10.").string.string == "At $5 or $10.")
        let streaming = render("Answer.\n\n$$\n\\frac{a}{b", midStream: true).string
        precondition(streaming.string == "Answer.\n…")
        let dots = (streaming.string as NSString).range(of: "…")
        precondition(
            (streaming.attribute(.paragraphStyle, at: dots.location, effectiveRange: nil) as? NSParagraphStyle)?
                .alignment == .center)
        precondition(render(#"Roots are \(x = \frac{1}{"#, midStream: true).string.string == "Roots are ")

        guard let engine = MathLayoutEngine(size: 20),
            let fraction = MathFormula(tex: #"\frac{a}{b}"#, source: "", display: true),
            let letter = MathFormula(tex: "a", source: "", display: true),
            let squared = MathFormula(tex: "a^2", source: "", display: false),
            let wide = MathFormula(tex: String(repeating: "a + ", count: 40) + "a", source: "", display: true)
        else { fatalError("STIX Two Math and formulas must load") }
        let a = engine.layout(letter)
        let over = engine.layout(fraction)
        precondition(over.ascent > a.ascent && over.descent > a.descent)
        precondition(engine.layout(squared).ascent > a.ascent)
        let box = engine.layout(wide)
        let cell = MathAttachmentCell(box: box, color: .labelColor, label: "formula")
        let container = NSTextContainer(size: CGSize(width: 200, height: 1000))
        container.lineFragmentPadding = 0
        let frame = cell.cellFrame(
            for: container, proposedLineFragment: CGRect(x: 0, y: 0, width: 200, height: 20),
            glyphPosition: .zero, characterIndex: 0)
        precondition(box.width > 200 && abs(frame.width - 200) < 0.5)
        precondition(abs(frame.height / frame.width - box.height / box.width) < 0.001)
        precondition(cell.accessibilityLabel() == "formula")
        print("Quick Action Markdown rendering checks passed")
    }
}
