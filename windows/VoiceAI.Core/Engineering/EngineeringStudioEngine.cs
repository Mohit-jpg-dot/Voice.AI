using System;
using System.Collections.Generic;

namespace VoiceAI.Core.Engineering
{
    public enum CadBackend
    {
        OpenScad,
        CadQuery
    }

    public sealed record PhysicsSimResult(string SimulationType, string Summary, IReadOnlyDictionary<string, double> Metrics);

    public interface IEngineeringStudioEngine
    {
        string GenerateCadCode(string shape, CadBackend backend, double widthMm = 60, double heightMm = 40, double depthMm = 10);
        PhysicsSimResult SimulateProjectile(double velocityMs, double angleDeg, double gravity = 9.81);
        PhysicsSimResult SimulateThermal(double powerWatts, double ambientCelsius = 25.0, double thermalResistanceCW = 1.8);
    }

    /// <summary>
    /// Parametric OpenSCAD/CadQuery CAD generator and deterministic physics simulator for Windows VoiceAI.Core.
    /// </summary>
    public sealed class EngineeringStudioEngine : IEngineeringStudioEngine
    {
        public static EngineeringStudioEngine Shared { get; } = new EngineeringStudioEngine();

        public string GenerateCadCode(string shape, CadBackend backend, double widthMm = 60, double heightMm = 40, double depthMm = 10)
        {
            if (backend == CadBackend.CadQuery)
            {
                return $"import cadquery as cq\npart = cq.Workplane(\"XY\").box({widthMm}, {heightMm}, {depthMm}).hole(5.0)";
            }
            return $"// OpenSCAD {shape} ({widthMm}x{heightMm}x{depthMm}mm)\ncube([{widthMm}, {heightMm}, {depthMm}]);";
        }

        public PhysicsSimResult SimulateProjectile(double velocityMs, double angleDeg, double gravity = 9.81)
        {
            double rad = angleDeg * System.Math.PI / 180.0;
            double vx = velocityMs * System.Math.Cos(rad);
            double vy = velocityMs * System.Math.Sin(rad);
            double t = (2.0 * vy) / gravity;
            double range = vx * t;
            double hMax = (vy * vy) / (2.0 * gravity);
            return new PhysicsSimResult(
                "Projectile Kinematics",
                $"Range {range:F2}m, Max Height {hMax:F2}m, Time {t:F2}s",
                new Dictionary<string, double> { ["range_m"] = range, ["max_height_m"] = hMax, ["flight_time_s"] = t });
        }

        public PhysicsSimResult SimulateThermal(double powerWatts, double ambientCelsius = 25.0, double thermalResistanceCW = 1.8)
        {
            double deltaT = powerWatts * thermalResistanceCW;
            double steady = ambientCelsius + deltaT;
            return new PhysicsSimResult(
                "Steady-State Thermal",
                $"Junction Temp {steady:F1}C (+{deltaT:F1}C)",
                new Dictionary<string, double> { ["steady_temp_c"] = steady, ["delta_t_c"] = deltaT });
        }
    }
}

