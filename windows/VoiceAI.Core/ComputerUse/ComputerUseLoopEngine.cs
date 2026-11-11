using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using VoiceAI.Core.Security;

namespace VoiceAI.Core.ComputerUse
{
    public enum ComputerUseOperation
    {
        Click,
        Write,
        Press,
        OpenApp,
        Wait,
        Done
    }

    public sealed record ComputerUseAction(
        ComputerUseOperation Operation,
        double? NormalizedX = null,
        double? NormalizedY = null,
        string? Label = null,
        string? Content = null,
        string? Summary = null);

    public sealed class ComputerUseLoopEngine
    {
        public static ComputerUseLoopEngine Shared { get; } = new ComputerUseLoopEngine();

        private static readonly string[] RiskyMarkers =
        {
            "delete", "remove", "erase", "send", "pay", "purchase", "install", "shutdown", "restart", "sudo", "terminal"
        };

        public static bool IsRisky(ComputerUseAction action, string goal = "")
        {
            string hay = $"{action.Label} {action.Content} {action.Summary} {goal}".ToLowerInvariant();
            return RiskyMarkers.Any(hay.Contains);
        }

        public static (int X, int Y) ToPhysicalScreenPoint(
            double normalizedX, double normalizedY, int widthPx, int heightPx, double dpiScale = 1.0)
        {
            double cx = System.Math.Clamp(normalizedX, 0.005, 0.995);
            double cy = System.Math.Clamp(normalizedY, 0.005, 0.995);
            double scale = dpiScale > 0 ? dpiScale : 1.0;
            return ((int)((cx * widthPx) / scale), (int)((cy * heightPx) / scale));
        }

        public async Task<(bool Success, string Summary, int StepsExecuted)> RunAgentTaskAsync(
            string goal,
            Func<int, IReadOnlyList<ComputerUseAction>, Task<ComputerUseAction>> decideNext,
            int maxSteps = 15,
            Func<ComputerUseAction, Task<bool>>? confirm = null,
            CancellationToken cancellationToken = default)
        {
            var history = new List<ComputerUseAction>();
            int limit = System.Math.Clamp(maxSteps, 1, 20);

            for (int step = 1; step <= limit; step++)
            {
                if (cancellationToken.IsCancellationRequested)
                    return (false, "Stopped.", history.Count);

                var action = await decideNext(step, history);
                if (action.Operation == ComputerUseOperation.Done)
                    return (true, SecretRedactor.Redact(action.Summary ?? "Done."), history.Count);

                if (IsRisky(action, goal))
                {
                    bool approved = confirm != null && await confirm(action);
                    if (!approved) return (false, "Cancelled.", history.Count);
                }

                history.Add(action);
            }

            return (false, $"I couldn't finish within the {limit}-step limit.", history.Count);
        }
    }
}

