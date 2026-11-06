using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using VoiceAI.Core.Brain;
using VoiceAI.Core.Grammar;
using VoiceAI.Core.Math;
using VoiceAI.Core.Memory;
using VoiceAI.Core.Tools;

namespace VoiceAI.Core.Tests
{
    public static class TestRunner
    {
        private static int _passed = 0;
        private static int _failed = 0;

        private static void AssertTrue(bool condition, string testName)
        {
            if (condition)
            {
                _passed++;
                Console.WriteLine($"  ✓ PASS: {testName}");
            }
            else
            {
                _failed++;
                Console.WriteLine($"  ✗ FAIL: {testName}");
            }
        }

        private static void AssertEqual<T>(T actual, T expected, string testName)
        {
            if (EqualityComparer<T>.Default.Equals(actual, expected))
            {
                _passed++;
                Console.WriteLine($"  ✓ PASS: {testName}");
            }
            else
            {
                _failed++;
                Console.WriteLine($"  ✗ FAIL: {testName} (Expected: '{expected}', Got: '{actual}')");
            }
        }

        public static async Task<int> Main(string[] args)
        {
            Console.WriteLine("=================================================================");
            Console.WriteLine("Voice.AI Windows Core Verification Test Suite (.NET 10/8)");
            Console.WriteLine($"Timestamp: {DateTime.UtcNow:u}");
            Console.WriteLine("=================================================================\n");

            TestMathEngine();
            TestCommandGrammar();
            TestEncryptedHistoryIsolation();
            await TestToolExecutionPlanner();
            await TestGoogleSearchFreeEngine();

            Console.WriteLine("\n=================================================================");
            Console.WriteLine($"Test Run Completed: {_passed} PASSED, {_failed} FAILED");
            Console.WriteLine("=================================================================");

            return _failed > 0 ? 1 : 0;
        }

        // -------------------------------------------------------------
        // Suite 1: Math Engine Tests
        // -------------------------------------------------------------
        private static void TestMathEngine()
        {
            Console.WriteLine("[Suite 1] Deterministic Math Engine");

            var math = MathEngine.Shared;

            var r1 = math.Evaluate("what is 25 * 4");
            AssertTrue(r1 != null && r1.Answer == "100", "25 * 4 evaluates to 100");

            var r2 = math.Evaluate("what is 25 * 4?");
            AssertTrue(r2 != null && r2.Answer == "100", "25 * 4? evaluates with question mark");

            var r3 = math.Evaluate("25 into 4 kitna hota hai");
            AssertTrue(r3 != null && r3.Answer == "100", "Hindi phrasing 'into ... kitna hota hai' evaluates to 100");

            var r4 = math.Evaluate("what is 15 percent of 80");
            AssertTrue(r4 != null && r4.Answer == "12", "15% of 80 evaluates to 12");

            var r5 = math.Evaluate("square root of 144");
            AssertTrue(r5 != null && r5.Answer == "12", "square root of 144 evaluates to 12");

            var r6 = math.Evaluate("2 to the power of 8");
            AssertTrue(r6 != null && r6.Answer == "256", "2^8 evaluates to 256");

            var r7 = math.Evaluate("10 plus 20 minus 5");
            AssertTrue(r7 != null && r7.Answer == "25", "10 + 20 - 5 evaluates to 25");
        }

        // -------------------------------------------------------------
        // Suite 2: Command Grammar & Intent Routing
        // -------------------------------------------------------------
        private static void TestCommandGrammar()
        {
            Console.WriteLine("\n[Suite 2] Hindi, Hinglish & English Command Grammar");

            var grammar = CommandGrammarEngine.Shared;

            var c1 = grammar.Parse("WhatsApp kholo");
            AssertEqual(c1.Intent, CommandIntent.OpenApp, "WhatsApp kholo -> OpenApp");
            AssertEqual(c1.TargetApp, "WhatsApp", "Target app is WhatsApp");

            var c2 = grammar.Parse("open Google Chrome");
            AssertEqual(c2.Intent, CommandIntent.OpenApp, "open Google Chrome -> OpenApp");

            var c3 = grammar.Parse("Spotify band karo");
            AssertEqual(c3.Intent, CommandIntent.CloseApp, "Spotify band karo -> CloseApp");
            AssertEqual(c3.TargetApp, "Spotify", "Close target is Spotify");

            var c4 = grammar.Parse("close the app");
            AssertEqual(c4.Intent, CommandIntent.CloseApp, "close the app -> CloseApp");

            var c5 = grammar.Parse("volume kam karo");
            AssertEqual(c5.Intent, CommandIntent.VolumeDown, "volume kam karo -> VolumeDown");

            var c6 = grammar.Parse("turn up the volume");
            AssertEqual(c6.Intent, CommandIntent.VolumeUp, "turn up the volume -> VolumeUp");

            var c7 = grammar.Parse("play the current video");
            AssertEqual(c7.Intent, CommandIntent.MediaPlay, "play the current video -> MediaPlay");

            var c8 = grammar.Parse("video chalao");
            AssertEqual(c8.Intent, CommandIntent.MediaPlay, "video chalao -> MediaPlay");

            var c9 = grammar.Parse("change it to next");
            AssertEqual(c9.Intent, CommandIntent.MediaNext, "change it to next -> MediaNext");

            var c10 = grammar.Parse("agla gana");
            AssertEqual(c10.Intent, CommandIntent.MediaNext, "agla gana -> MediaNext");

            var c11 = grammar.Parse("take a screenshot");
            AssertEqual(c11.Intent, CommandIntent.TakeScreenshot, "take a screenshot -> TakeScreenshot");

            var c12 = grammar.Parse("lock computer");
            AssertEqual(c12.Intent, CommandIntent.LockComputer, "lock computer -> LockComputer");
        }

        // -------------------------------------------------------------
        // Suite 3: Encrypted History Isolation & Redaction
        // -------------------------------------------------------------
        private static void TestEncryptedHistoryIsolation()
        {
            Console.WriteLine("\n[Suite 3] Encrypted History & Strict Account Isolation");

            var history = EncryptedHistoryManager.Shared;
            string accA = "user_alpha_" + Guid.NewGuid();
            string accB = "user_beta_" + Guid.NewGuid();

            try
            {
                string rawWithKeys = "Here is my secret sk-1234567890abcdef1234567890 and claude sk-ant-abcdef1234567890123456";
                string redacted = history.RedactSecrets(rawWithKeys);

                AssertTrue(!redacted.Contains("sk-1234567890"), "OpenAI key redacted");
                AssertTrue(!redacted.Contains("sk-ant-abcdef"), "Anthropic key redacted");
                AssertTrue(redacted.Contains("[REDACTED_API_KEY]"), "Placeholder present");

                history.AppendMessage(accA, "user", rawWithKeys);
                history.AppendMessage(accA, "assistant", "Done.");

                var loadedA = history.LoadMessages(accA);
                AssertEqual(loadedA.Count, 2, "Account A has 2 messages");
                AssertTrue(loadedA[0].Content.Contains("[REDACTED_API_KEY]"), "Stored message is safely redacted");

                var loadedB = history.LoadMessages(accB);
                AssertEqual(loadedB.Count, 0, "Account B CANNOT see Account A messages (Isolated)");
            }
            finally
            {
                history.ClearHistory(accA);
                history.ClearHistory(accB);
            }
        }

        // -------------------------------------------------------------
        // Suite 4: Tool Execution Planner & Approvals
        // -------------------------------------------------------------
        private static async Task TestToolExecutionPlanner()
        {
            Console.WriteLine("\n[Suite 4] Tool Execution Planner & Safety Approvals");

            var planner = ToolExecutionPlanner.Shared;

            var waPlan = planner.FormulatePlan("WhatsApp pe message bhejo to John saying meeting confirmed");
            AssertTrue(waPlan.NeedsUserApproval, "Sending messaging requires user approval");
            AssertTrue(waPlan.ApprovalWarning.Contains("confirmation"), "Approval warning presented");
            AssertEqual(waPlan.Steps.Count, 3, "Formulated 3 steps for message flow");

            var termPlan = planner.FormulatePlan("open Windows Terminal");
            AssertTrue(!termPlan.NeedsUserApproval, "Opening terminal does not require consequential approval");

            var execResult = await planner.ExecuteAsync(termPlan, async step =>
            {
                await Task.Delay(20);
                return true;
            });

            AssertTrue(execResult.Success, "Plan executed successfully");
            AssertTrue(execResult.ElapsedSeconds > 0, "Elapsed seconds recorded");
            AssertTrue(execResult.SpokenReport.Contains("Ho gaya"), "Spoken report includes 'Ho gaya'");
            AssertTrue(execResult.SpokenReport.Contains("second lage"), "Spoken report includes elapsed time");
        }

        // -------------------------------------------------------------
        // Suite 5: Google Search Free Engine
        // -------------------------------------------------------------
        private static async Task TestGoogleSearchFreeEngine()
        {
            Console.WriteLine("\n[Suite 5] Google Search Free Engine & Fallbacks");

            var engine = GoogleSearchFreeEngine.Shared;

            var mathCard = await engine.AnswerQuestionAsync("what is 25 * 4");
            AssertTrue(mathCard.IsDirectAnswer, "Math query returns direct answer");
            AssertTrue(mathCard.AnswerText.Contains("100"), "Math query evaluated to 100");
            AssertEqual(mathCard.MethodLabel, "via Built-in Calculator", "Method is Built-in Calculator");

            var searchCard = await engine.AnswerQuestionAsync("quantum computing breakthroughs");
            AssertTrue(searchCard.SourceUrl.Contains("google.com/search"), "Fallback points to Google search URL");
            AssertTrue(searchCard.SourceUrl.Contains("quantum%20computing"), "Query is URL-encoded");
        }
    }
}
