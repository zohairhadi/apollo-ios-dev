import Foundation

public struct TemplateString: ExpressibleByStringInterpolation, CustomStringConvertible {

  private let value: String
  private let lastLineWasRemoved: Bool

  public init(_ string: String) {
    self.value = string
    lastLineWasRemoved = false
  }

  public init(stringLiteral: String) {
    self.init(stringLiteral)
  }

  public init(stringInterpolation: StringInterpolation) {
    self.value = stringInterpolation.output
    self.lastLineWasRemoved = stringInterpolation.lastLineWasRemoved
  }

  public init(_ stringInterpolation: StringInterpolation) {
    self.value = stringInterpolation.output
    self.lastLineWasRemoved = stringInterpolation.lastLineWasRemoved
  }

  public var description: String { value }

  public var isEmpty: Bool { description.isEmpty }

  public struct StringInterpolation: StringInterpolationProtocol {

    fileprivate var lastLineWasRemoved = false
    private var buffer: String

    fileprivate var output: String {
      if lastLineWasRemoved && buffer.hasSuffix("\n") {
        return String(buffer.dropLast())
      }
      return buffer
    }

    public init(literalCapacity: Int, interpolationCount: Int) {
      var string = String()
      string.reserveCapacity(literalCapacity)
      self.buffer = string
    }

    public mutating func appendLiteral(_ literal: StringLiteralType) {
      guard !literal.isEmpty else { return }
      defer { lastLineWasRemoved = false }

      if lastLineWasRemoved && literal.hasPrefix("\n") {
        buffer.append(contentsOf: literal.dropFirst())
      } else {
        buffer.append(literal)
      }
    }

    public mutating func appendInterpolation(_ string: StaticString) {
      appendInterpolation(string.description)
    }

    public mutating func appendInterpolation(_ template: TemplateString) {
      if template.isEmpty {
        removeLineIfEmpty()

      } else {
        appendInterpolation(template.description)
      }
    }

    public mutating func appendInterpolation(section: TemplateString) {
      appendInterpolation(section)

      if section.isEmpty && buffer.hasSuffix("\n") {
        buffer.removeLast()
      }
    }

    private static let whitespaceNotNewline = Set(" \t")

    public mutating func appendInterpolation(_ string: String) {
      let indent = getCurrentIndent()

      if indent.isEmpty {
        appendLiteral(string)
      } else {
        let indentedString = string
          .split(separator: "\n", omittingEmptySubsequences: false)
          .joinedAsLines(withIndent: indent)

        appendLiteral(indentedString)
      }
    }

    private func getCurrentIndent() -> String {
      let reverseBuffer = buffer.reversed()
      let startOfLine = reverseBuffer.firstIndex(of: "\n") ?? reverseBuffer.endIndex
      return String(reverseBuffer.prefix(upTo: startOfLine).reversed().prefix {
        TemplateString.StringInterpolation.whitespaceNotNewline.contains($0)
      })
    }

    public mutating func appendInterpolation<T>(
      _ sequence: T,
      separator: String = ",\n",
      terminator: String? = nil
    ) where T: Sequence, T.Element == TemplateString {
      appendInterpolation(
        sequence.lazy.map { $0.description },
        separator: separator,
        terminator: terminator
      )
    }

    @_disfavoredOverload
    public mutating func appendInterpolation<T>(
      _ sequence: T,
      separator: String = ",\n",
      terminator: String? = nil
    ) where T: Sequence, T.Element: CustomStringConvertible {
      appendInterpolation(
        sequence.lazy.map { $0.description },
        separator: separator,
        terminator: terminator
      )
    }

    public mutating func appendInterpolation<T>(
      _ sequence: T,
      separator: String = ",\n",
      terminator: String? = nil
    ) where T: LazySequenceProtocol, T.Element: CustomStringConvertible {
      appendInterpolation(
        forEachIn: sequence,
        separator: separator,
        terminator: terminator,
        { TemplateString($0.description) }
      )
    }

    public mutating func appendInterpolation<T>(
      list: T,
      separator: String = ",\n",
      terminator: String? = nil
    ) where T: Collection, T.Element: CustomStringConvertible {
      let shouldWrapInNewlines = list.count > 1
      if shouldWrapInNewlines { appendInterpolation("\n  ") }
      appendInterpolation(list, separator: separator, terminator: terminator)
      if shouldWrapInNewlines { appendInterpolation("\n") }
    }

    @_disfavoredOverload
    public mutating func appendInterpolation<T>(
      list: T,
      separator: String = ",\n",
      terminator: String? = nil
    ) where T: Collection, T.Element: CustomDebugStringConvertible {
      let shouldWrapInNewlines = list.count > 1
      if shouldWrapInNewlines { appendLiteral("\n  ") }
      appendInterpolation(
        list.map { $0.debugDescription },
        separator: separator,
        terminator: terminator
      )
      if shouldWrapInNewlines { appendInterpolation("\n") }
    }

    // MARK: For Each

    public mutating func appendInterpolation<T>(
      forEachIn sequence: T,
      separator: String = ",\n",
      terminator: String? = nil,
      _ template: (T.Element) throws -> TemplateString?
    ) rethrows where T: Sequence {
      var iterator = sequence.makeIterator()
      var resultString = ""

      while let element = iterator.next(),
            let elementString = try template(element)?.description {
        resultString.append(
          resultString.isEmpty ?
          elementString : separator + elementString
        )
      }

      guard !resultString.isEmpty else {
        removeLineIfEmpty()
        return
      }

      appendInterpolation(resultString)
      if let terminator = terminator {
        appendInterpolation(terminator)
      }
    }

    // MARK: While

    public mutating func appendInterpolation(
      while whileBlock: @autoclosure () -> Bool,
      _ template: () -> TemplateString,
      separator: String = ",\n",
      terminator: String? = nil
    ) {
      var list: [TemplateString] = []
      while whileBlock() {
        list.append(template())
      }
      self.appendInterpolation(list, separator: separator, terminator: terminator)
    }

    // MARK: If

    public mutating func appendInterpolation(
      if bool: Bool,
      _ template: @autoclosure () -> TemplateString,
      else: @autoclosure () -> TemplateString? = nil
    ) {
      if bool {
        appendInterpolation(template())
      } else if let elseTemplate = `else`() {
        appendInterpolation(elseTemplate)
      } else {
        removeLineIfEmpty()
      }
    }

    /// MARK: If Let

    public mutating func appendInterpolation<T>(
      ifLet optional: Optional<T>,
      _ includeBlock: (T) -> TemplateString
    ) {
      if let element = optional {
        appendInterpolation(includeBlock(element))
      } else {
        removeLineIfEmpty()
      }
    }

    @_disfavoredOverload
    public mutating func appendInterpolation<T>(
      ifLet optional: Optional<T>,
      where whereBlock: ((T) -> Bool)? = nil,
      _ includeBlock: (T) -> TemplateString,
      else: @autoclosure () -> TemplateString? = nil
    ) {
      if let element = optional, whereBlock?(element) ?? true {
        appendInterpolation(includeBlock(element))
      } else if let elseTemplate = `else`() {
        appendInterpolation(elseTemplate.description)
      } else {
        removeLineIfEmpty()
      }
    }

    @_disfavoredOverload
    public mutating func appendInterpolation<T>(
      ifLet optional: Optional<T>,
      where whereBlock: @autoclosure @escaping () -> Bool = true,
      _ includeBlock: (T) -> TemplateString,
      else: @autoclosure () -> TemplateString? = nil
    ) {
      appendInterpolation(
        ifLet: optional,
        where: { _ in whereBlock() },
        includeBlock,
        else: `else`()
      )
    }

    @_disfavoredOverload
    public mutating func appendInterpolation<T>(
      ifLet optional: Optional<T>,
      where whereBlock: ((T) -> Bool)? = nil,
      _ includeBlock: @autoclosure () -> TemplateString,
      else: @autoclosure () -> TemplateString? = nil
    ) {
      appendInterpolation(
        ifLet: optional,
        where: whereBlock,
        { _ in includeBlock() },
        else: `else`()
      )
    }

    @_disfavoredOverload
    public mutating func appendInterpolation<T>(
      ifLet optional: Optional<T>,
      _ includeBlock: (T) -> TemplateString,
      else: @autoclosure () -> TemplateString? = nil
    ) {
      appendInterpolation(
        ifLet: optional,
        where: nil,
        includeBlock,
        else: `else`()
      )
    }

    // MARK: Comments

    public mutating func appendInterpolation(
      comment: String?
    ) {
      appendInterpolation(comment: comment, withLinePrefix: "//")
    }

    private mutating func appendInterpolation(
      comment: String?,
      withLinePrefix prefix: String
    ) {
      guard let comment = comment, !comment.isEmpty else {
        removeLineIfEmpty()
        return
      }

      let components = comment
        .split(separator: "\n", omittingEmptySubsequences: false)
        .joinedAsCommentLines(withLinePrefix: prefix)

      appendInterpolation(components)
    }

    public mutating func appendInterpolation(
      documentation: String?
    ) {
      appendInterpolation(comment: documentation, withLinePrefix: "///")
    }

    // MARK: JSON

    mutating func appendInterpolation(json jsonData: Data) {
      appendInterpolation(String(decoding: jsonData, as: UTF8.self))
    }

    // MARK: - Helpers

    public mutating func removeLineIfEmpty() {
      let slice = substringToStartOfLine()
      if slice.allSatisfy(\.isWhitespace) {
        buffer.removeLast(slice.count)
        lastLineWasRemoved = true
      }
    }

    private func substringToStartOfLine() -> Slice<ReversedCollection<String>> {
      return buffer.reversed().prefix { !$0.isNewline }
    }

  }

}

/// Can be used to concatenate a `TemplateString` and `String` directly.
/// This bypasses `TemplateString` interpolation logic such as indentation calculation.
public func +(lhs: String, rhs: TemplateString) -> TemplateString {
  TemplateString(lhs + rhs.description)
}

// MARK: - Extensions

extension Array where Element == Substring {
  func joinedAsLines(withIndent indent: String) -> String {
    var iterator = self.makeIterator()
    var string = iterator.next()?.description ?? ""

    while let nextLine = iterator.next() {
      string += "\n"
      if !nextLine.isEmpty {
        string += indent + nextLine
      }
    }

    return string
  }

  fileprivate func joinedAsCommentLines(withLinePrefix prefix: String) -> String {
    var string = ""

    func add(line: Substring) {
      string += prefix
      if !line.isEmpty {
        string += " "
        string += line
      }
    }
    var iterator = self.makeIterator()
    if let firstLine = iterator.next() { add(line: firstLine) }

    while let nextLine = iterator.next() {
      string += "\n"
      add(line: nextLine)
    }

    return string
  }
}
