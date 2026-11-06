using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading.Tasks;

namespace VoiceAI.Core.Tools
{
    public record ToolStep(string ActionName, string Parameters, bool RequiresApproval, string Description);

    public record ExecutionPlan(
        string Goal,
        IReadOnlyList<ToolStep> Steps,
        bool NeedsUserApproval,
        string ApprovalWarning
    );

    public record ExecutionResult(
        bool Success,
        string Summary,
        double ElapsedSeconds,
        string SpokenReport
    );

    /// <summary>
    /// Multi-step tool execution planner with safety gates for Windows.
    /// Requires exact preview and approval for consequential actions (e.g. sending messages).
    /// </summary>
    public sealed class ToolExecutionPlanner
    {
        public static ToolExecutionPlanner Shared { get; } = new ToolExecutionPlanner();

        private ToolExecutionPlanner() { }

        public ExecutionPlan FormulatePlan(string instruction)
        {
            string lower = instruction.ToLowerInvariant();
            var steps = new List<ToolStep>();
            bool needsApproval = false;
            string warning = "";

            if (lower.Contains("whatsapp") && (lower.Contains("bhejo") || lower.Contains("send") || lower.Contains("message")))
            {
                steps.Add(new ToolStep("launch_app", "WhatsApp", false, "Launch WhatsApp Desktop application"));
                steps.Add(new ToolStep("prepare_draft", instruction, false, "Prepare message draft in chat text area"));
                steps.Add(new ToolStep("send_message", instruction, true, "Send the prepared message to recipient"));
                needsApproval = true;
                warning = "Sending a message via WhatsApp requires your confirmation.";
                return new ExecutionPlan(instruction, steps, needsApproval, warning);
            }

            if (lower.Contains("terminal") || lower.Contains("cmd") || lower.Contains("powershell"))
            {
                steps.Add(new ToolStep("launch_app", "Windows Terminal", false, "Open Windows Terminal"));
                steps.Add(new ToolStep("execute_allowlisted_command", instruction, false, "Run diagnostic command"));
                return new ExecutionPlan(instruction, steps, false, "");
            }

            steps.Add(new ToolStep("execute_action", instruction, false, $"Execute {instruction}"));
            return new ExecutionPlan(instruction, steps, false, "");
        }

        public async Task<ExecutionResult> ExecuteAsync(ExecutionPlan plan, Func<ToolStep, Task<bool>> stepExecutor)
        {
            var sw = Stopwatch.StartNew();

            foreach (var step in plan.Steps)
            {
                bool stepSuccess = await stepExecutor(step);
                if (!stepSuccess)
                {
                    sw.Stop();
                    return new ExecutionResult(false, $"Failed on step: {step.Description}", sw.Elapsed.TotalSeconds, "Action could not be completed.");
                }
            }

            sw.Stop();
            double seconds = System.Math.Max(0.1, System.Math.Round(sw.Elapsed.TotalSeconds, 1));
            string spoken = $"Ho gaya, {seconds:F1} second lage.";

            return new ExecutionResult(true, $"Successfully completed: {plan.Goal}", seconds, spoken);
        }
    }
}
