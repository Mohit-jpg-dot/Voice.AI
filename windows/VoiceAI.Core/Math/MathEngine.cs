using System;
using System.Data;
using System.Globalization;
using System.Text.RegularExpressions;

namespace VoiceAI.Core.Math
{
    public record MathCalculationResult(
        string Expression,
        string Answer,
        string SpokenText,
        string DisplaySummary
    );

    /// <summary>
    /// Deterministic, offline mathematical evaluation engine for Windows.
    /// Evaluates arithmetic, percentages, powers, square roots, and conversational word problems in English and Hindi.
    /// </summary>
    public sealed class MathEngine
    {
        public static MathEngine Shared { get; } = new MathEngine();

        private MathEngine() { }

        public bool IsMathQuery(string rawText)
        {
            if (string.IsNullOrWhiteSpace(rawText)) return false;
            string text = rawText.ToLowerInvariant().Trim();

            string[] keywords =
            {
                "calculate", "solve", "evaluate", "plus", "minus", "multiplied by",
                "multiply by", "multiply", "divided by", "divide by", "times", "into",
                "percent of", "percentage of", "% of",
                "square root of", "sqrt", "cube root of", "to the power of",
                "kitna hota", "kitna hoga", "kitna hua", "kya hoga", "kya hai",
                "guna", "guda", "bhaag", "jod"
            };

            foreach (var kw in keywords)
            {
                if (text.Contains(kw)) return true;
            }

            bool hasDigit = false;
            bool hasOperator = false;
            foreach (char c in text)
            {
                if (char.IsDigit(c)) hasDigit = true;
                if ("+-*/x×÷^%".IndexOf(c) >= 0) hasOperator = true;
            }

            if (hasDigit && hasOperator)
            {
                if (text.Contains("-") && text.Split('-').Length == 3) return false; // Date
                return true;
            }

            return false;
        }

        public MathCalculationResult? Evaluate(string rawText)
        {
            if (string.IsNullOrWhiteSpace(rawText)) return null;

            string clean = rawText
                .Replace("what is the answer to ", "", StringComparison.OrdinalIgnoreCase)
                .Replace("what is the value of ", "", StringComparison.OrdinalIgnoreCase)
                .Replace("what is ", "", StringComparison.OrdinalIgnoreCase)
                .Replace("calculate ", "", StringComparison.OrdinalIgnoreCase)
                .Replace("solve ", "", StringComparison.OrdinalIgnoreCase)
                .Replace("evaluate ", "", StringComparison.OrdinalIgnoreCase)
                .Replace("how much is ", "", StringComparison.OrdinalIgnoreCase)
                .Replace("can you calculate ", "", StringComparison.OrdinalIgnoreCase)
                .Replace("please solve ", "", StringComparison.OrdinalIgnoreCase)
                .Replace("kitna hota hai", "", StringComparison.OrdinalIgnoreCase)
                .Replace("kitna hoga", "", StringComparison.OrdinalIgnoreCase)
                .Replace("kitna hua", "", StringComparison.OrdinalIgnoreCase)
                .Replace("kya hoga", "", StringComparison.OrdinalIgnoreCase)
                .Replace("kya hai", "", StringComparison.OrdinalIgnoreCase)
                .Replace("batao", "", StringComparison.OrdinalIgnoreCase)
                .Replace("bata do", "", StringComparison.OrdinalIgnoreCase)
                .Replace("is equal to", "", StringComparison.OrdinalIgnoreCase)
                .Replace("equals", "", StringComparison.OrdinalIgnoreCase)
                .Replace("equal to", "", StringComparison.OrdinalIgnoreCase)
                .Replace("?", "")
                .Replace("=", "")
                .Trim();

            if (string.IsNullOrEmpty(clean)) return null;

            // 1. Percentages ("15% of 80", "15 percent of 80")
            var percent = EvaluatePercentage(clean);
            if (percent != null) return percent;

            // 2. Square roots ("square root of 144", "sqrt 64")
            var sqrt = EvaluateSquareRoot(clean);
            if (sqrt != null) return sqrt;

            // 3. Powers ("2 to the power of 8", "3^4")
            var power = EvaluatePower(clean);
            if (power != null) return power;

            // 4. Standard arithmetic ("25 * 4", "15 + 27", "5 into 10", "100 / 4")
            var arithmetic = EvaluateArithmetic(clean);
            if (arithmetic != null) return arithmetic;

            return null;
        }

        private MathCalculationResult? EvaluatePercentage(string text)
        {
            string lower = text.ToLowerInvariant();
            if (!lower.Contains("percent of") && !lower.Contains("% of") && !lower.Contains("percentage of"))
                return null;

            string norm = lower
                .Replace("percentage of", "% of")
                .Replace("percent of", "% of")
                .Replace("%of", "% of");

            string[] parts = norm.Split(new[] { "% of" }, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length != 2) return null;

            string pctStr = Regex.Replace(parts[0], @"[^\d.]", "");
            string baseStr = Regex.Replace(parts[1], @"[^\d.]", "");

            if (!double.TryParse(pctStr, NumberStyles.Any, CultureInfo.InvariantCulture, out double p)) return null;
            if (!double.TryParse(baseStr, NumberStyles.Any, CultureInfo.InvariantCulture, out double b)) return null;

            double res = (p / 100.0) * b;
            string formattedRes = FormatNumber(res);
            string formattedP = FormatNumber(p);
            string formattedB = FormatNumber(b);

            string expr = $"{formattedP}% of {formattedB}";
            return new MathCalculationResult(
                Expression: expr,
                Answer: formattedRes,
                SpokenText: $"{expr} is {formattedRes}.",
                DisplaySummary: $"{expr} = {formattedRes}"
            );
        }

        private MathCalculationResult? EvaluateSquareRoot(string text)
        {
            string lower = text.ToLowerInvariant();
            if (!lower.Contains("square root of") && !lower.StartsWith("sqrt"))
                return null;

            string numStr = lower
                .Replace("square root of", "")
                .Replace("sqrt", "")
                .Replace("(", "")
                .Replace(")", "")
                .Trim();

            if (!double.TryParse(numStr, NumberStyles.Any, CultureInfo.InvariantCulture, out double num) || num < 0)
                return null;

            double res = System.Math.Sqrt(num);
            string formattedRes = FormatNumber(res);
            string formattedNum = FormatNumber(num);

            string expr = $"√{formattedNum}";
            return new MathCalculationResult(
                Expression: expr,
                Answer: formattedRes,
                SpokenText: $"The square root of {formattedNum} is {formattedRes}.",
                DisplaySummary: $"{expr} = {formattedRes}"
            );
        }

        private MathCalculationResult? EvaluatePower(string text)
        {
            string lower = text.ToLowerInvariant();
            if (lower.Contains("to the power of"))
            {
                var parts = lower.Split(new[] { "to the power of" }, StringSplitOptions.RemoveEmptyEntries);
                if (parts.Length == 2 &&
                    double.TryParse(parts[0].Trim(), NumberStyles.Any, CultureInfo.InvariantCulture, out double b) &&
                    double.TryParse(parts[1].Trim(), NumberStyles.Any, CultureInfo.InvariantCulture, out double exp))
                {
                    double res = System.Math.Pow(b, exp);
                    string fb = FormatNumber(b);
                    string fexp = FormatNumber(exp);
                    string fres = FormatNumber(res);
                    return new MathCalculationResult(
                        Expression: $"{fb}^{fexp}",
                        Answer: fres,
                        SpokenText: $"{fb} to the power of {fexp} is {fres}.",
                        DisplaySummary: $"{fb}^{fexp} = {fres}"
                    );
                }
            }

            if (lower.Contains("^"))
            {
                var parts = lower.Split('^');
                if (parts.Length == 2 &&
                    double.TryParse(parts[0].Trim(), NumberStyles.Any, CultureInfo.InvariantCulture, out double b) &&
                    double.TryParse(parts[1].Trim(), NumberStyles.Any, CultureInfo.InvariantCulture, out double exp))
                {
                    double res = System.Math.Pow(b, exp);
                    string fb = FormatNumber(b);
                    string fexp = FormatNumber(exp);
                    string fres = FormatNumber(res);
                    return new MathCalculationResult(
                        Expression: $"{fb}^{fexp}",
                        Answer: fres,
                        SpokenText: $"{fb} to the power of {fexp} is {fres}.",
                        DisplaySummary: $"{fb}^{fexp} = {fres}"
                    );
                }
            }

            return null;
        }

        private MathCalculationResult? EvaluateArithmetic(string text)
        {
            string exprStr = text.ToLowerInvariant()
                .Replace("multiplied by", "*")
                .Replace("multiply by", "*")
                .Replace("multiply", "*")
                .Replace("times", "*")
                .Replace("x", "*")
                .Replace("×", "*")
                .Replace("into", "*")
                .Replace("divided by", "/")
                .Replace("divide by", "/")
                .Replace("divided", "/")
                .Replace("÷", "/")
                .Replace("plus", "+")
                .Replace("minus", "-")
                .Replace("?", "")
                .Replace("=", "")
                .Trim();

            // Validate valid math characters
            foreach (char c in exprStr)
            {
                if (!char.IsDigit(c) && "+-*/(). ".IndexOf(c) < 0)
                    return null;
            }

            if (exprStr.IndexOfAny(new[] { '+', '-', '*', '/' }) < 0)
                return null;

            try
            {
                var table = new DataTable();
                var computeResult = table.Compute(exprStr, string.Empty);
                if (computeResult == null || computeResult == DBNull.Value) return null;

                double val = Convert.ToDouble(computeResult, CultureInfo.InvariantCulture);
                if (double.IsNaN(val) || double.IsInfinity(val))
                {
                    return new MathCalculationResult(
                        Expression: exprStr,
                        Answer: "Undefined",
                        SpokenText: "The result is undefined (cannot divide by zero).",
                        DisplaySummary: $"{exprStr} = Undefined"
                    );
                }

                string formattedVal = FormatNumber(val);
                string displayExpr = exprStr
                    .Replace("*", " × ")
                    .Replace("/", " ÷ ")
                    .Replace("+", " + ")
                    .Replace("-", " - ")
                    .Trim();

                return new MathCalculationResult(
                    Expression: displayExpr,
                    Answer: formattedVal,
                    SpokenText: $"{displayExpr} = {formattedVal}.",
                    DisplaySummary: $"{displayExpr} = {formattedVal}"
                );
            }
            catch
            {
                return null;
            }
        }

        private static string FormatNumber(double val)
        {
            if (System.Math.Abs(val - System.Math.Round(val)) < 0.0000001)
            {
                return ((long)System.Math.Round(val)).ToString(CultureInfo.InvariantCulture);
            }
            return val.ToString("0.######", CultureInfo.InvariantCulture);
        }
    }
}
