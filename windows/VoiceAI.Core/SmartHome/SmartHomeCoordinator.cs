using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using VoiceAI.Core.Events;
using VoiceAI.Core.Tools;

namespace VoiceAI.Core.SmartHome
{
    public enum SmartHomeDeviceKind
    {
        Light,
        Lock,
        Thermostat,
        Scene,
        SecuritySystem,
        Switch
    }

    public sealed record SmartHomeDevice(
        string Id,
        string Name,
        string Room,
        SmartHomeDeviceKind Kind,
        string Bridge,
        string State,
        string EntityId);

    public interface ISmartHomeCoordinator
    {
        IReadOnlyList<SmartHomeDevice> AllDevices();
        PermissionTier RequiredTier(SmartHomeDeviceKind kind, bool isReadOnly);
        Task<(bool Success, string Summary, PermissionTier Tier)> ExecuteAsync(
            string deviceQuery,
            string action,
            string? value = null,
            Func<SmartHomeDevice, string, Task<bool>>? approvalHandler = null);
    }

    /// <summary>
    /// Home Assistant / HomeKit / MQTT Smart Home coordinator with strict CONSEQUENTIAL approval
    /// gating for locks and security alarms.
    /// </summary>
    public sealed class SmartHomeCoordinator : ISmartHomeCoordinator
    {
        public static SmartHomeCoordinator Shared { get; } = new SmartHomeCoordinator();

        private readonly object _lock = new();
        private readonly List<SmartHomeDevice> _devices;

        public SmartHomeCoordinator()
        {
            _devices = new List<SmartHomeDevice>
            {
                new("sh_living_lights", "Living Room Lights", "Living Room", SmartHomeDeviceKind.Light, "Home Assistant", "off", "light.living_room"),
                new("sh_thermostat", "Main Thermostat", "Hallway", SmartHomeDeviceKind.Thermostat, "Home Assistant", "22C", "climate.hallway"),
                new("sh_front_lock", "Front Door Lock", "Entry", SmartHomeDeviceKind.Lock, "HomeKit", "locked", "lock.front_door"),
                new("sh_security_alarm", "Home Security Alarm", "Whole Home", SmartHomeDeviceKind.SecuritySystem, "MQTT", "armed", "alarm.home_security"),
                new("sh_movie_scene", "Movie Night Scene", "Living Room", SmartHomeDeviceKind.Scene, "Home Assistant", "idle", "scene.movie_night")
            };
        }

        public IReadOnlyList<SmartHomeDevice> AllDevices()
        {
            lock (_lock) return _devices.ToList();
        }

        public PermissionTier RequiredTier(SmartHomeDeviceKind kind, bool isReadOnly)
        {
            if (isReadOnly) return PermissionTier.ReadOnly;
            return (kind == SmartHomeDeviceKind.Lock || kind == SmartHomeDeviceKind.SecuritySystem)
                ? PermissionTier.Consequential
                : PermissionTier.Reversible;
        }

        public async Task<(bool Success, string Summary, PermissionTier Tier)> ExecuteAsync(
            string deviceQuery,
            string action,
            string? value = null,
            Func<SmartHomeDevice, string, Task<bool>>? approvalHandler = null)
        {
            string q = (deviceQuery ?? "").Trim().ToLowerInvariant();
            string act = (action ?? "").Trim().ToLowerInvariant();

            SmartHomeDevice? device;
            lock (_lock)
            {
                device = _devices.FirstOrDefault(d =>
                    q.Contains(d.Name.ToLowerInvariant()) ||
                    d.Name.ToLowerInvariant().Contains(q) ||
                    (q.Contains("light") && d.Kind == SmartHomeDeviceKind.Light) ||
                    ((q.Contains("lock") || q.Contains("door")) && d.Kind == SmartHomeDeviceKind.Lock) ||
                    (q.Contains("alarm") && d.Kind == SmartHomeDeviceKind.SecuritySystem) ||
                    (q.Contains("thermostat") && d.Kind == SmartHomeDeviceKind.Thermostat));
            }

            if (device == null)
                return (false, $"No smart home device matching '{deviceQuery}'.", PermissionTier.ReadOnly);

            bool isRead = act is "status" or "read" or "check";
            var tier = RequiredTier(device.Kind, isRead);
            if (isRead)
                return (true, $"{device.Name} is currently {device.State}.", tier);

            if (tier == PermissionTier.Consequential)
            {
                bool approved = approvalHandler != null && await approvalHandler(device, act);
                if (!approved)
                {
                    return (false, $"Cancelled: approval required before changing security device '{device.Name}'.", tier);
                }
            }

            string nextState = act switch
            {
                "on" or "turn_on" => "on",
                "off" or "turn_off" => "off",
                "lock" => "locked",
                "unlock" => "unlocked",
                "arm" => "armed",
                "disarm" => "disarmed",
                "set_temperature" => $"{value ?? "22"}C",
                _ => value ?? act
            };

            lock (_lock)
            {
                int idx = _devices.FindIndex(d => d.Id == device.Id);
                if (idx >= 0) _devices[idx] = device with { State = nextState };
            }

            EventBus.Shared.Publish(VoiceEvent.Create(
                SystemEventKind.Custom,
                "SmartHomeCoordinator",
                new Dictionary<string, string>
                {
                    ["device"] = device.Name,
                    ["state"] = nextState,
                    ["tier"] = tier.ToString()
                },
                tier == PermissionTier.Consequential ? VoiceEventSeverity.Notice : VoiceEventSeverity.Info));

            return (true, $"{device.Name} is now {nextState}.", tier);
        }
    }
}

