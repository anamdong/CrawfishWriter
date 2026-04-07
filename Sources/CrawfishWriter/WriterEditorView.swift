import SwiftUI
import AppKit

struct WriterEditorView: NSViewRepresentable {
    @Binding var text: String
    var focusMode: FocusMode
    var onUserEdit: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 2
        layoutManager.addTextContainer(textContainer)

        let textView = WriterTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize), textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.autoresizingMask = [.width]
        textView.string = text
        textView.focusMode = focusMode
        textView.scheduleStyling(reason: .fullRefresh)

        scrollView.documentView = textView
        context.coordinator.attach(textView: textView, scrollView: scrollView)

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = context.coordinator.textView else { return }
        textView.focusMode = focusMode

        if textView.string != text {
            context.coordinator.isApplyingExternalChange = true
            let currentSelection = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            let location = min(currentSelection.location, length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
            textView.scheduleStyling(reason: .fullRefresh)
            context.coordinator.isApplyingExternalChange = false
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: WriterEditorView
        weak var textView: WriterTextView?
        var isApplyingExternalChange = false
        private var boundsObserver: NSObjectProtocol?

        init(parent: WriterEditorView) {
            self.parent = parent
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
        }

        func attach(textView: WriterTextView, scrollView: NSScrollView) {
            self.textView = textView
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak textView] _ in
                textView?.scheduleStyling(reason: .visibleRangeChanged)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            guard !isApplyingExternalChange else { return }
            let value = textView.string
            parent.text = value
            parent.onUserEdit(value)
            textView.scheduleStyling(reason: .textChanged)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            textView?.scheduleStyling(reason: .selectionChanged)
        }
    }
}

final class WriterTextView: NSTextView {
    enum StylingReason {
        case textChanged
        case selectionChanged
        case visibleRangeChanged
        case focusModeChanged
        case fullRefresh
    }

    enum PartOfSpeech {
        case noun
        case verb
        case adjective
    }

    struct POSHighlight {
        let range: NSRange
        let kind: PartOfSpeech
    }

    struct StylingInput {
        let text: String
        let selection: NSRange
        let visibleRange: NSRange
        let focusMode: FocusMode
        let isDarkMode: Bool
    }

    struct StylePlan {
        let textLength: Int
        let focusRange: NSRange?
        let isDarkMode: Bool
        let highlights: [POSHighlight]
    }

    var focusMode: FocusMode = .off {
        didSet {
            guard oldValue != focusMode else { return }
            scheduleStyling(reason: .focusModeChanged)
        }
    }

    private static let editorFont = NSFont.monospacedSystemFont(ofSize: 19, weight: .regular)
    private static let cursorColorLight = NSColor(calibratedRed: 0.76, green: 0.46, blue: 0.46, alpha: 0.95)
    private static let cursorColorDark = NSColor(calibratedRed: 0.86, green: 0.56, blue: 0.56, alpha: 0.95)
    private static let baseParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 8
        style.paragraphSpacing = 12
        style.lineBreakMode = .byWordWrapping
        return style
    }()

    private let stylingQueue = DispatchQueue(label: "quietwrite.styling", qos: .userInitiated)
    private var pendingWork: DispatchWorkItem?
    private var styleGeneration: Int = 0
    private var applyingStyle = false
    private var isUpdatingColumnLayout = false

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configureEditor()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureEditor()
    }

    deinit {
        pendingWork?.cancel()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateColumnLayout()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateCursorColor()
        scheduleStyling(reason: .fullRefresh)
    }

    func scheduleStyling(reason: StylingReason) {
        guard !applyingStyle else { return }

        styleGeneration += 1
        let generation = styleGeneration
        let input = captureStylingInput()
        pendingWork?.cancel()

        let delay: TimeInterval
        switch reason {
        case .focusModeChanged, .fullRefresh:
            delay = 0
        case .selectionChanged, .visibleRangeChanged:
            delay = 0.03
        case .textChanged:
            delay = 0.09
        }

        let work = DispatchWorkItem { [weak self] in
            let plan = Self.makeStylePlan(from: input)
            DispatchQueue.main.async {
                guard let self else { return }
                guard generation == self.styleGeneration else { return }
                self.apply(plan: plan)
            }
        }
        pendingWork = work
        stylingQueue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func configureEditor() {
        allowsUndo = true
        isEditable = true
        isSelectable = true
        isRichText = false
        importsGraphics = false
        usesFindBar = true

        isAutomaticDashSubstitutionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = true
        isGrammarCheckingEnabled = false
        isContinuousSpellCheckingEnabled = false

        drawsBackground = false
        backgroundColor = .clear
        textColor = .labelColor
        updateCursorColor()
        font = Self.editorFont

        isHorizontallyResizable = false
        isVerticallyResizable = true
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        textContainer?.lineFragmentPadding = 2
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = false

        updateColumnLayout()
        refreshTypingAttributes()
    }

    private func updateColumnLayout() {
        guard !isUpdatingColumnLayout else { return }
        guard let textContainer else { return }

        let targetColumnWidth: CGFloat = 760
        let horizontalInset = max(28, (bounds.width - targetColumnWidth) / 2)
        let desiredInset = NSSize(width: horizontalInset, height: 72)

        let usableWidth = max(240, bounds.width - (horizontalInset * 2))
        let desiredContainerSize = NSSize(width: usableWidth, height: .greatestFiniteMagnitude)

        let epsilon: CGFloat = 0.5
        let insetChanged =
            abs(textContainerInset.width - desiredInset.width) > epsilon ||
            abs(textContainerInset.height - desiredInset.height) > epsilon
        let sizeChanged =
            abs(textContainer.containerSize.width - desiredContainerSize.width) > epsilon ||
            abs(textContainer.containerSize.height - desiredContainerSize.height) > epsilon

        guard insetChanged || sizeChanged else { return }

        isUpdatingColumnLayout = true
        defer { isUpdatingColumnLayout = false }

        if insetChanged {
            textContainerInset = desiredInset
        }
        if sizeChanged {
            textContainer.containerSize = desiredContainerSize
        }
    }

    private func refreshTypingAttributes() {
        typingAttributes = Self.baseAttributes(foreground: .labelColor)
    }

    private func updateCursorColor() {
        let isDarkMode = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        insertionPointColor = isDarkMode ? Self.cursorColorDark : Self.cursorColorLight
    }

    private func captureStylingInput() -> StylingInput {
        let content = string
        let totalLength = (content as NSString).length
        let selection = Self.clamp(range: selectedRange(), upperBound: totalLength)
        let visibleRange = Self.clamp(range: visibleCharacterRange(totalLength: totalLength), upperBound: totalLength)
        let isDarkMode = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        return StylingInput(
            text: content,
            selection: selection,
            visibleRange: visibleRange,
            focusMode: focusMode,
            isDarkMode: isDarkMode
        )
    }

    private func visibleCharacterRange(totalLength: Int) -> NSRange {
        guard totalLength > 0 else { return NSRange(location: 0, length: 0) }
        guard let layoutManager, let textContainer else {
            return NSRange(location: 0, length: totalLength)
        }

        let visibleRect = enclosingScrollView?.contentView.documentVisibleRect ?? bounds
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        if glyphRange.length == 0 {
            return NSRange(location: min(selectedRange().location, totalLength), length: 0)
        }

        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        return Self.clamp(range: characterRange, upperBound: totalLength)
    }

    private static func makeStylePlan(from input: StylingInput) -> StylePlan {
        let nsText = input.text as NSString
        let length = nsText.length
        let focusRange = focusedRange(for: input.focusMode, selection: input.selection, text: nsText)
        let analysisRange = analysisRange(
            textLength: length,
            selection: input.selection,
            visibleRange: input.visibleRange,
            focusRange: focusRange
        )

        var highlights: [POSHighlight] = []
        if analysisRange.length > 0 {
            let tagger = NSLinguisticTagger(tagSchemes: [.lexicalClass], options: 0)
            tagger.string = input.text
            let options: NSLinguisticTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]

            tagger.enumerateTags(in: analysisRange, unit: .word, scheme: .lexicalClass, options: options) { tag, tokenRange, _ in
                if let focusRange, NSIntersectionRange(tokenRange, focusRange).length == 0 {
                    return
                }

                let kind: PartOfSpeech?
                switch tag {
                case .noun:
                    kind = .noun
                case .verb:
                    kind = .verb
                case .adjective:
                    kind = .adjective
                default:
                    kind = nil
                }

                guard let kind else { return }
                highlights.append(POSHighlight(range: tokenRange, kind: kind))
            }
        }

        return StylePlan(
            textLength: length,
            focusRange: focusRange,
            isDarkMode: input.isDarkMode,
            highlights: highlights
        )
    }

    private func apply(plan: StylePlan) {
        guard let textStorage else { return }
        guard textStorage.length == plan.textLength else {
            scheduleStyling(reason: .fullRefresh)
            return
        }

        applyingStyle = true

        let fullRange = NSRange(location: 0, length: textStorage.length)
        let baseColor = NSColor.labelColor
        let dimColor = baseColor.withAlphaComponent(0.34)

        textStorage.beginEditing()
        if let focusRange = plan.focusRange, focusRange.length > 0 {
            textStorage.setAttributes(Self.baseAttributes(foreground: dimColor), range: fullRange)
            if NSMaxRange(focusRange) <= textStorage.length {
                textStorage.addAttributes(Self.baseAttributes(foreground: baseColor), range: focusRange)
            }
        } else {
            textStorage.setAttributes(Self.baseAttributes(foreground: baseColor), range: fullRange)
        }

        for highlight in plan.highlights {
            guard NSMaxRange(highlight.range) <= textStorage.length else { continue }
            textStorage.addAttribute(
                .foregroundColor,
                value: Self.highlightColor(for: highlight.kind, darkMode: plan.isDarkMode),
                range: highlight.range
            )
        }
        textStorage.endEditing()

        refreshTypingAttributes()
        applyingStyle = false
    }

    private static func focusedRange(for mode: FocusMode, selection: NSRange, text: NSString) -> NSRange? {
        guard text.length > 0 else { return nil }
        let selection = clamp(range: selection, upperBound: text.length)
        let location = min(selection.location, max(0, text.length - 1))
        let seed = NSRange(location: location, length: 0)

        switch mode {
        case .off:
            return nil
        case .sentence:
            return sentenceRange(in: text, around: location)
        case .paragraph:
            return text.paragraphRange(for: seed)
        }
    }

    private static func sentenceRange(in text: NSString, around location: Int) -> NSRange {
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }
        let probe = min(max(0, location), text.length - 1)
        let fullRange = NSRange(location: 0, length: text.length)

        let tagger = NSLinguisticTagger(tagSchemes: [.tokenType], options: 0)
        tagger.string = text as String

        var foundRange: NSRange?
        tagger.enumerateTags(
            in: fullRange,
            unit: .sentence,
            scheme: .tokenType,
            options: [.omitWhitespace]
        ) { _, sentenceRange, stop in
            let upper = sentenceRange.location + sentenceRange.length
            if (probe >= sentenceRange.location && probe < upper) || probe == upper {
                foundRange = sentenceRange
                stop.pointee = true
            }
        }

        return foundRange ?? text.paragraphRange(for: NSRange(location: probe, length: 0))
    }

    private static func analysisRange(
        textLength: Int,
        selection: NSRange,
        visibleRange: NSRange,
        focusRange: NSRange?
    ) -> NSRange {
        guard textLength > 0 else { return NSRange(location: 0, length: 0) }

        if textLength <= 120_000 {
            return NSRange(location: 0, length: textLength)
        }

        var range = expandedRange(around: selection, by: 5_000, upperBound: textLength)
        let expandedVisible = expandedRange(around: visibleRange, by: 2_000, upperBound: textLength)
        range = NSUnionRange(range, expandedVisible)

        if let focusRange {
            let expandedFocus = expandedRange(around: focusRange, by: 1_200, upperBound: textLength)
            range = NSUnionRange(range, expandedFocus)
        }

        return clamp(range: range, upperBound: textLength)
    }

    private static func expandedRange(around range: NSRange, by amount: Int, upperBound: Int) -> NSRange {
        let safeRange = clamp(range: range, upperBound: upperBound)
        let lowerBound = max(0, safeRange.location - amount)
        let upperRangeBound = min(upperBound, safeRange.location + safeRange.length + amount)
        return NSRange(location: lowerBound, length: max(0, upperRangeBound - lowerBound))
    }

    private static func clamp(range: NSRange, upperBound: Int) -> NSRange {
        guard upperBound >= 0 else {
            return NSRange(location: 0, length: 0)
        }

        let location = max(0, min(range.location, upperBound))
        let unclampedUpperBound = range.location + max(0, range.length)
        let upperRangeBound = max(location, min(unclampedUpperBound, upperBound))
        return NSRange(location: location, length: max(0, upperRangeBound - location))
    }

    private static func baseAttributes(foreground: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: editorFont,
            .paragraphStyle: baseParagraphStyle,
            .foregroundColor: foreground
        ]
    }

    private static func highlightColor(for partOfSpeech: PartOfSpeech, darkMode: Bool) -> NSColor {
        switch (partOfSpeech, darkMode) {
        case (.noun, false):
            return NSColor(calibratedRed: 0.30, green: 0.43, blue: 0.62, alpha: 0.90)
        case (.verb, false):
            return NSColor(calibratedRed: 0.30, green: 0.50, blue: 0.39, alpha: 0.90)
        case (.adjective, false):
            return NSColor(calibratedRed: 0.55, green: 0.43, blue: 0.25, alpha: 0.90)
        case (.noun, true):
            return NSColor(calibratedRed: 0.58, green: 0.71, blue: 0.90, alpha: 0.92)
        case (.verb, true):
            return NSColor(calibratedRed: 0.55, green: 0.80, blue: 0.65, alpha: 0.92)
        case (.adjective, true):
            return NSColor(calibratedRed: 0.88, green: 0.76, blue: 0.53, alpha: 0.92)
        }
    }
}
