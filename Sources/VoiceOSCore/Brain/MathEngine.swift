import Foundation

public struct MathCalculationResult: Sendable, Equatable {
    public let expression: String
    public let answer: String
    public let spokenText: String
    public let displaySummary: String
}

/// Instant, offline, deterministic mathematical evaluation engine.
/// Handles arithmetic, percentages, powers, square roots, and conversational word problems.
public final class MathEngine: Sendable {
    public static let shared = MathEngine()
    
    private init() {}
    
    /// Checks if a string represents a mathematical or arithmetic question.
    public func isMathQuery(_ rawText: String) -> Bool {
        let text = rawText.lowercased()
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !text.isEmpty else { return false }
        
        // 1. Explicit math keywords (English & Hindi/Hinglish)
        let mathKeywords = [
            "calculate", "solve", "evaluate", "plus", "minus", "multiplied by",
            "multiply by", "multiply", "divided by", "divide by", "times", "into",
            "percent of", "percentage of", "% of",
            "square root of", "sqrt", "cube root of", "to the power of",
            "kitna hota", "kitna hoga", "kitna hua", "kya hoga", "kya hai",
            "guna", "guda", "bhaag", "jod"
        ]
        for kw in mathKeywords {
            if text.contains(kw) { return true }
        }
        
        // 2. Contains numbers and arithmetic operators
        let hasDigit = text.contains { $0.isNumber }
        let hasOperator = text.contains { "+-*/x×÷^%".contains($0) }
        
        if hasDigit && hasOperator {
            // Verify it's not a date, time or version number like "2026-11-06" or "v1.0.0"
            if text.contains("-") && text.components(separatedBy: "-").count == 3 {
                return false
            }
            return true
        }
        
        return false
    }
    
    /// Evaluates a math expression and returns a structured calculation result.
    public func evaluate(_ rawText: String) -> MathCalculationResult? {
        let clean = rawText
            .replacingOccurrences(of: "what is the answer to ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "what is the value of ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "what is ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "calculate ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "solve ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "evaluate ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "how much is ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "can you calculate ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "please solve ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "kitna hota hai", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "kitna hoga", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "kitna hua", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "kya hoga", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "kya hai", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "batao", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "bata do", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "is equal to", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "equals", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "equal to", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        
        guard !clean.isEmpty else { return nil }
        
        // Case A: Percentages ("15% of 80", "20 percent of 150", "what is 7.5% of 200")
        if let percentResult = evaluatePercentage(clean) {
            return percentResult
        }
        
        // Case B: Square root ("square root of 144", "sqrt 64", "sqrt(144)")
        if let sqrtResult = evaluateSquareRoot(clean) {
            return sqrtResult
        }
        
        // Case C: Power ("2 to the power of 8", "3^4", "5 power 3")
        if let powerResult = evaluatePower(clean) {
            return powerResult
        }
        
        // Case D: Standard Arithmetic ("25 * 4", "15 + 27", "120 / 4", "10 plus 20 minus 5")
        if let arithmeticResult = evaluateArithmetic(clean) {
            return arithmeticResult
        }
        
        return nil
    }
    
    // MARK: - Percentage Evaluation
    
    private func evaluatePercentage(_ text: String) -> MathCalculationResult? {
        let lower = text.lowercased()
        guard lower.contains("percent of") || lower.contains("% of") || lower.contains("percentage of") else {
            return nil
        }
        
        var normalized = lower
            .replacingOccurrences(of: "percentage of", with: "% of")
            .replacingOccurrences(of: "percent of", with: "% of")
            .replacingOccurrences(of: "%of", with: "% of")
        
        let parts = normalized.components(separatedBy: "% of")
        guard parts.count == 2,
              let percentVal = Double(parts[0].filter { $0.isNumber || $0 == "." }),
              let baseVal = Double(parts[1].filter { $0.isNumber || $0 == "." }) else {
            return nil
        }
        
        let result = (percentVal / 100.0) * baseVal
        let formattedResult = formatNumber(result)
        let formattedPercent = formatNumber(percentVal)
        let formattedBase = formatNumber(baseVal)
        
        let expr = "\(formattedPercent)% of \(formattedBase)"
        return MathCalculationResult(
            expression: expr,
            answer: formattedResult,
            spokenText: "\(expr) is \(formattedResult).",
            displaySummary: "\(expr) = \(formattedResult)"
        )
    }
    
    // MARK: - Square Root Evaluation
    
    private func evaluateSquareRoot(_ text: String) -> MathCalculationResult? {
        let lower = text.lowercased()
        guard lower.contains("square root of") || lower.hasPrefix("sqrt") else {
            return nil
        }
        
        let numStr = lower
            .replacingOccurrences(of: "square root of", with: "")
            .replacingOccurrences(of: "sqrt", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let num = Double(numStr), num >= 0 else { return nil }
        
        let result = sqrt(num)
        let formattedResult = formatNumber(result)
        let formattedNum = formatNumber(num)
        
        let expr = "√\(formattedNum)"
        return MathCalculationResult(
            expression: expr,
            answer: formattedResult,
            spokenText: "The square root of \(formattedNum) is \(formattedResult).",
            displaySummary: "\(expr) = \(formattedResult)"
        )
    }
    
    // MARK: - Power Evaluation
    
    private func evaluatePower(_ text: String) -> MathCalculationResult? {
        let lower = text.lowercased()
        if lower.contains("to the power of") {
            let parts = lower.components(separatedBy: "to the power of")
            guard parts.count == 2,
                  let base = Double(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let exponent = Double(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return nil
            }
            let result = pow(base, exponent)
            let formattedBase = formatNumber(base)
            let formattedExp = formatNumber(exponent)
            let formattedResult = formatNumber(result)
            return MathCalculationResult(
                expression: "\(formattedBase)^\(formattedExp)",
                answer: formattedResult,
                spokenText: "\(formattedBase) to the power of \(formattedExp) is \(formattedResult).",
                displaySummary: "\(formattedBase)^\(formattedExp) = \(formattedResult)"
            )
        }
        
        if lower.contains("^") {
            let parts = lower.components(separatedBy: "^")
            guard parts.count == 2,
                  let base = Double(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let exponent = Double(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return nil
            }
            let result = pow(base, exponent)
            let formattedBase = formatNumber(base)
            let formattedExp = formatNumber(exponent)
            let formattedResult = formatNumber(result)
            return MathCalculationResult(
                expression: "\(formattedBase)^\(formattedExp)",
                answer: formattedResult,
                spokenText: "\(formattedBase) to the power of \(formattedExp) is \(formattedResult).",
                displaySummary: "\(formattedBase)^\(formattedExp) = \(formattedResult)"
            )
        }
        
        return nil
    }
    
    // MARK: - Standard Arithmetic Evaluation
    
    private func evaluateArithmetic(_ text: String) -> MathCalculationResult? {
        var exprStr = text.lowercased()
            .replacingOccurrences(of: "multiplied by", with: "*")
            .replacingOccurrences(of: "multiply by", with: "*")
            .replacingOccurrences(of: "multiply", with: "*")
            .replacingOccurrences(of: "times", with: "*")
            .replacingOccurrences(of: "x", with: "*")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "into", with: "*")
            .replacingOccurrences(of: "divided by", with: "/")
            .replacingOccurrences(of: "divide by", with: "/")
            .replacingOccurrences(of: "divided", with: "/")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "plus", with: "+")
            .replacingOccurrences(of: "minus", with: "-")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        
        // Remove spaces inside numbers or formatting
        let allowedChars = CharacterSet(charactersIn: "0123456789.+-*/() ")
        guard exprStr.unicodeScalars.allSatisfy({ allowedChars.contains($0) }) else {
            return nil
        }
        
        // Ensure there is at least one operator
        guard exprStr.contains("+") || exprStr.contains("-") || exprStr.contains("*") || exprStr.contains("/") else {
            return nil
        }
        
        // Use double precision for divisions (e.g. replace "5/2" with "5.0/2.0")
        let tokenized = exprStr.components(separatedBy: " ").joined()
        
        // Format for NSExpression: ensure floats are used
        let nsExprFormat = prepareForNSExpression(tokenized)
        
        let expression = NSExpression(format: nsExprFormat)
        guard let value = expression.expressionValue(with: nil, context: nil) as? NSNumber else {
            return nil
        }
        
        let doubleVal = value.doubleValue
        guard !doubleVal.isNaN && !doubleVal.isInfinite else {
            return MathCalculationResult(
                expression: tokenized,
                answer: "Undefined",
                spokenText: "The result is undefined (cannot divide by zero).",
                displaySummary: "\(tokenized) = Undefined"
            )
        }
        
        let formattedResult = formatNumber(doubleVal)
        let displayExpr = tokenized
            .replacingOccurrences(of: "*", with: " × ")
            .replacingOccurrences(of: "/", with: " ÷ ")
            .replacingOccurrences(of: "+", with: " + ")
            .replacingOccurrences(of: "-", with: " - ")
        
        return MathCalculationResult(
            expression: displayExpr,
            answer: formattedResult,
            spokenText: "\(displayExpr) = \(formattedResult).",
            displaySummary: "\(displayExpr) = \(formattedResult)"
        )
    }
    
    private func prepareForNSExpression(_ raw: String) -> String {
        var result = ""
        var currentNum = ""
        
        for ch in raw {
            if ch.isNumber || ch == "." {
                currentNum.append(ch)
            } else {
                if !currentNum.isEmpty {
                    if !currentNum.contains(".") {
                        currentNum.append(".0")
                    }
                    result.append(currentNum)
                    currentNum = ""
                }
                result.append(ch)
            }
        }
        
        if !currentNum.isEmpty {
            if !currentNum.contains(".") {
                currentNum.append(".0")
            }
            result.append(currentNum)
        }
        
        return result
    }
    
    private func formatNumber(_ val: Double) -> String {
        if floor(val) == val && abs(val) < 1_000_000_000_000.0 {
            return String(format: "%.0f", val)
        } else {
            let str = String(format: "%.4f", val)
            // Trim trailing zeroes
            var trimmed = str
            while trimmed.hasSuffix("0") {
                trimmed.removeLast()
            }
            if trimmed.hasSuffix(".") {
                trimmed.removeLast()
            }
            return trimmed
        }
    }
}

