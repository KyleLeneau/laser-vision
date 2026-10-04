import LaserShaderTypes
import ShowModel

/// The dome backdrop the lasers are composed over; each surrounding provides its own.
public struct SkyStyle: Sendable, Hashable {
    public var zenithColor: LaserColor
    public var horizonColor: LaserColor
    /// 0…1 brightness of the procedural star field.
    public var starIntensity: Float
    /// 0…1 visibility of dome panel seams (a physical planetarium dome).
    public var seamIntensity: Float

    public init(zenithColor: LaserColor, horizonColor: LaserColor, starIntensity: Float, seamIntensity: Float) {
        self.zenithColor = zenithColor
        self.horizonColor = horizonColor
        self.starIntensity = starIntensity
        self.seamIntensity = seamIntensity
    }

    func uniforms(laserBrightness: Float, time: Double, encodeSRGB: Bool) -> LaserSkyUniforms {
        var uniforms = LaserSkyUniforms()
        uniforms.zenithColor = zenithColor.linear
        uniforms.horizonColor = horizonColor.linear
        uniforms.starIntensity = starIntensity
        uniforms.seamIntensity = seamIntensity
        uniforms.laserBrightness = laserBrightness
        uniforms.time = Float(time)
        uniforms.encodeSRGB = encodeSRGB ? 1 : 0
        return uniforms
    }
}
