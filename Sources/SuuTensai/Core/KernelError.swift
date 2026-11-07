import Foundation

public struct KernelError: Error, CustomStringConvertible, LocalizedError {
    public let message: String
    public let span: SourceSpan

    public var description: String { "\(span.start.line):\(span.start.column): kernel: \(message)" }
    public var errorDescription: String? { description }

    public func render(source: String, fileName: String = "<input>") -> String {
        // Reuse the frontend's source excerpt/Unicode-column renderer.
        let rendered = FrontendError(phase: .parser, message: message, span: span)
            .render(source: source, fileName: fileName)
        return rendered.replacingOccurrences(of: ": parser: ", with: ": kernel: ")
    }
}

public struct KernelReport: Sendable {
    public let declarations: [String]
    /// Axioms are explicit assumptions, including those used transitively.
    public let axioms: [String]
}

struct KernelLimits {
    var maxSteps = 1_000_000
    var maxDepth = 64
    var maxBinders = 32
}
