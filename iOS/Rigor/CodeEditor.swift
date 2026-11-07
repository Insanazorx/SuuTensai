import SwiftUI
import UIKit
import SuuTensai

/// UIKit editörü seçim, undo ve klavye kısayollarını korur.
struct CodeEditor: UIViewRepresentable {
    @Binding var text: String
    let diagnostic: RigorDiagnostic?
    let navigation: EditorNavigation?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        view.textColor = .label
        view.tintColor = .systemTeal
        view.textContainerInset = UIEdgeInsets(top: 20, left: 16, bottom: 32, right: 16)
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartDashesType = .no
        view.smartQuotesType = .no
        view.smartInsertDeleteType = .no
        view.spellCheckingType = .no
        view.keyboardType = .asciiCapable
        view.keyboardDismissMode = .interactive
        view.alwaysBounceVertical = true
        view.accessibilityLabel = "Rigor kod editörü"
        view.accessibilityIdentifier = "rigor.editor"
        view.inputAccessoryView = context.coordinator.accessory(for: view)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text {
            view.text = text
            view.selectedRange = NSRange(location: 0, length: 0)
            view.undoManager?.removeAllActions()
        }
        context.coordinator.decorate(view)
        if let navigation, navigation.id != context.coordinator.lastNavigation {
            context.coordinator.lastNavigation = navigation.id
            let range = context.coordinator.range(for: navigation.span, in: text)
            view.becomeFirstResponder()
            view.selectedRange = range
            view.scrollRangeToVisible(range)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CodeEditor
        var lastNavigation: UUID?
        weak var editor: UITextView?
        private var decoratedText: String?
        private var decoratedDiagnostic: RigorDiagnostic?
        private var highlights: [RigorHighlight] = []

        init(_ parent: CodeEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func accessory(for view: UITextView) -> UIView {
            editor = view
            return SymbolAccessoryView { [weak self] symbol in self?.editor?.insertText(symbol) }
        }

        /// Kernel ofsetleri UTF-8; UITextView aralıkları UTF-16 kullanır.
        func range(for span: SourceSpan, in source: String) -> NSRange {
            span.utf16Range(in: source)
        }

        func color(for kind: RigorHighlight.Kind) -> UIColor {
            switch kind {
            case .keyword: .systemPurple
            case .type: .systemIndigo
            case .function: .systemBlue
            case .number: .systemOrange
            case .string: .systemGreen
            case .comment: .secondaryLabel
            case .operator: .systemTeal
            case .hole: .systemRed
            }
        }

        func decorate(_ view: UITextView) {
            // IME'nin henüz tamamlanmamış metnine dokunma.
            guard view.markedTextRange == nil else { return }
            guard decoratedText != parent.text || decoratedDiagnostic != parent.diagnostic else { return }
            if decoratedText != parent.text {
                highlights = parent.text.utf8.count <= RigorChecker.maximumSourceBytes
                    ? RigorHighlighter.highlights(in: parent.text) : []
            }
            decoratedText = parent.text
            decoratedDiagnostic = parent.diagnostic
            let selection = view.selectedRange
            let storage = view.textStorage
            let all = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: UIColor.label, range: all)
            storage.removeAttribute(.underlineStyle, range: all)
            storage.removeAttribute(.underlineColor, range: all)
            storage.removeAttribute(.backgroundColor, range: all)
            for highlight in highlights where NSMaxRange(highlight.range) <= storage.length {
                storage.addAttribute(.foregroundColor, value: color(for: highlight.kind), range: highlight.range)
            }
            if let diagnostic = parent.diagnostic, diagnostic.fileName == "Taslak.rigor" {
                var selected = range(for: diagnostic.span, in: parent.text)
                if selected.length == 0, storage.length > 0 {
                    selected = (parent.text as NSString).rangeOfComposedCharacterSequence(at: min(selected.location, storage.length - 1))
                }
                if selected.length > 0, NSMaxRange(selected) <= storage.length {
                    storage.addAttributes([
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .underlineColor: UIColor.systemRed,
                        .backgroundColor: UIColor.systemRed.withAlphaComponent(0.09),
                    ], range: selected)
                }
            }
            storage.endEditing()
            view.selectedRange = selection
            view.typingAttributes = [
                .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular),
                .foregroundColor: UIColor.label,
            ]
        }
    }
}

@MainActor
private final class SymbolAccessoryView: UIView {
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 48) }

    init(insert: @escaping (String) -> Void) {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 48))
        autoresizingMask = [.flexibleWidth]
        backgroundColor = .secondarySystemBackground
        let scroll = SymbolScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceHorizontal = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.delaysContentTouches = false
        scroll.canCancelContentTouches = true
        scroll.isDirectionalLockEnabled = true
        scroll.accessibilityIdentifier = "rigor.symbols"
        scroll.accessibilityLabel = "Rigor sembolleri"
        addSubview(scroll)
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 6
        scroll.addSubview(stack)
        let symbols = ["{", "}", "(", ")", "->", "=>", "<", ">", ":"]
        for (index, symbol) in symbols.enumerated() {
            var configuration = UIButton.Configuration.plain()
            configuration.title = symbol
            configuration.baseForegroundColor = .systemTeal
            configuration.background.backgroundColor = .tertiarySystemFill
            configuration.background.cornerRadius = 8
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var result = attributes
                result.font = .monospacedSystemFont(ofSize: 18, weight: .medium)
                return result
            }
            let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in insert(symbol) })
            button.accessibilityIdentifier = "rigor.symbol.\(index)"
            button.accessibilityLabel = symbol
            button.widthAnchor.constraint(equalToConstant: symbol.count > 1 ? 52 : 44).isActive = true
            stack.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -2),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Tuşun üzerinde başlayan yatay sürükleme, tuşa basmayı iptal edip şeridi kaydırır.
@MainActor
private final class SymbolScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool { true }
}
