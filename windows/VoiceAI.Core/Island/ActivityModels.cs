// Ported from islandcn, MIT License, Copyright (c) 2026 Leo. Modified for C#.
// Pure-logic activity data models for Voice.AI's dynamic notch presentation engine (.NET Core).

using System;
using System.Collections.Generic;

namespace VoiceAI.Core.Island
{
    public enum IslandPresentationKind
    {
        Idle,
        Compact,
        Split,
        Expanded
    }

    public static class ActivityPriority
    {
        public const int Background = -10;
        public const int Standard = 0;
        public const int Media = 10;
        public const int Timer = 20;
        public const int Recording = 50;
        public const int Alert = 80;
        public const int ConsequentialApproval = 9999;
    }

    public class ActivitySlotContent
    {
        public string Text { get; set; } = string.Empty;
        public string? Symbol { get; set; }
        public string? Tint { get; set; }
        public double? EndsAt { get; set; }
        public double? Progress { get; set; }

        public static ActivitySlotContent FromText(string text) => new ActivitySlotContent { Text = text };
        public static ActivitySlotContent FromSymbol(string symbol, string? tint = null) => new ActivitySlotContent { Symbol = symbol, Tint = tint, Text = symbol };
        public static ActivitySlotContent FromProgress(double progress, string? tint = null) => new ActivitySlotContent { Progress = progress, Tint = tint, Text = $"{(int)(progress * 100)}%" };
    }

    public class ActivityCompactSlots
    {
        public ActivitySlotContent? Leading { get; set; }
        public ActivitySlotContent? Trailing { get; set; }
    }

    public class ActivityExpandedSlots
    {
        public ActivitySlotContent? Leading { get; set; }
        public ActivitySlotContent? Trailing { get; set; }
        public ActivitySlotContent? Center { get; set; }
        public ActivitySlotContent? Bottom { get; set; }
    }

    public class ActivityContent
    {
        public ActivityCompactSlots? Compact { get; set; }
        public ActivitySlotContent? Minimal { get; set; }
        public ActivityExpandedSlots? Expanded { get; set; }
    }

    public class ActivityOptions
    {
        public string Id { get; set; } = string.Empty;
        public string? Label { get; set; }
        public int Priority { get; set; } = ActivityPriority.Standard;
        public bool Alert { get; set; }
        public string? Group { get; set; }
        public bool IsSensitive { get; set; }
        public bool PersistsAcrossRestarts { get; set; }
        public ActivityContent Content { get; set; } = new ActivityContent();
        public Action? OnPress { get; set; }
    }

    public class ActivityUpdate
    {
        public ActivityCompactSlots? Compact { get; set; }
        public ActivitySlotContent? Minimal { get; set; }
        public ActivityExpandedSlots? Expanded { get; set; }
        public string? Label { get; set; }
        public int? Priority { get; set; }
        public bool? Alert { get; set; }
        public string? Transition { get; set; }
        public Action? OnPress { get; set; }
    }

    public class Activity
    {
        public string Id { get; set; } = string.Empty;
        public string Label { get; set; } = string.Empty;
        public int Priority { get; set; }
        public int Order { get; set; }
        public ActivityContent Content { get; set; } = new ActivityContent();
        public int Revision { get; set; }
        public string? Group { get; set; }
        public bool IsSensitive { get; set; }
        public bool PersistsAcrossRestarts { get; set; }
        public Action? OnPress { get; set; }
    }

    public class IslandScene
    {
        public IslandPresentationKind Presentation { get; set; } = IslandPresentationKind.Idle;
        public string ContentKey { get; set; } = "idle";
        public string Label { get; set; } = string.Empty;
        public string? PrimaryId { get; set; }
        public string? DetachedId { get; set; }

        public static IslandScene Idle => new IslandScene { Presentation = IslandPresentationKind.Idle, ContentKey = "idle", Label = string.Empty };
    }
}

