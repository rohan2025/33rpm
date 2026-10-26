import AppKit
import AVFoundation
import QuartzCore

/// Ambient motion layers. All run in Core Animation's render server and stop when the music does.
@MainActor
enum Ambient {
    /// Dust motes drifting in the lamp light. Each mote grows from nothing and fades out, so none pop.
    static func dust(frame: CGRect, amount: CGFloat) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.name = "dust"
        emitter.frame = frame
        emitter.emitterShape = .rectangle
        emitter.emitterMode = .surface
        emitter.emitterPosition = CGPoint(x: frame.width / 2, y: frame.height / 2)
        emitter.emitterSize = frame.size
        emitter.renderMode = .additive

        let mote = CAEmitterCell()
        mote.contents = Placeholders.softDot()
        mote.birthRate = Float(5 * max(0, amount))
        mote.lifetime = 16
        mote.lifetimeRange = 5
        mote.velocity = 3
        mote.velocityRange = 3
        mote.emissionRange = .pi * 2
        mote.yAcceleration = -0.35        // a slow rise in the warm air
        mote.scale = 0
        mote.scaleSpeed = 0.011
        mote.color = NSColor(red: 1, green: 0.88, blue: 0.7, alpha: 0.5).cgColor
        mote.alphaSpeed = -0.031
        emitter.emitterCells = [mote]

        // Only visible where the light is.
        let light = CAGradientLayer()
        light.type = .radial
        light.colors = [NSColor.white.cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        light.startPoint = CGPoint(x: 0.5, y: 0.5)
        light.endPoint = CGPoint(x: 1, y: 1)
        light.frame = emitter.bounds
        emitter.mask = light
        return emitter
    }

    /// Rain streaks falling across a window.
    static func rain(frame: CGRect, amount: CGFloat) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.name = "rain"
        emitter.frame = frame
        emitter.masksToBounds = true
        emitter.emitterShape = .line
        emitter.emitterPosition = CGPoint(x: frame.width / 2, y: -20)
        emitter.emitterSize = CGSize(width: frame.width * 1.2, height: 1)

        let drop = CAEmitterCell()
        drop.contents = Placeholders.rainStreak()
        drop.birthRate = Float(90 * max(0, amount))
        drop.velocity = 520
        drop.velocityRange = 120
        drop.emissionLongitude = .pi / 2 + 0.08   // down, with a slight slant (flipped geometry: +y is down)
        drop.lifetime = Float((frame.height + 60) / 400)
        drop.scale = 0.6
        drop.scaleRange = 0.3
        drop.color = NSColor(white: 0.85, alpha: 0.35).cgColor
        drop.alphaRange = 0.2
        emitter.emitterCells = [drop]
        return emitter
    }

    /// Gentle irregular dimming, like a filament on old wiring.
    static func flicker(amount: CGFloat) -> CAAnimation {
        let dips: [CGFloat] = [0, 0.35, 0.05, 0.2, 0.8, 0.1, 0.3, 0, 0.55, 0.15, 0]
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = dips.map { 1 - $0 * amount }
        anim.keyTimes = [0, 0.07, 0.12, 0.31, 0.34, 0.4, 0.58, 0.66, 0.71, 0.86, 1]
        anim.duration = 7.3
        anim.repeatCount = .infinity
        anim.isAdditive = false
        return anim
    }

    /// Maps scene.json blend names to Core Image compositing filters.
    static func compositingFilter(_ name: String?) -> Any? {
        switch name {
        case "screen": "screenBlendMode"
        case "add": "additionCompositing"
        case "softLight": "softLightBlendMode"
        case "overlay": "overlayBlendMode"
        case "multiply": "multiplyBlendMode"
        default: nil
        }
    }
}

/// One muted, looping player per video file, shared by every window showing the scene.
@MainActor
final class AmbientVideo {
    static let shared = AmbientVideo()

    private var url: URL?
    private(set) var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var wantsPlaying = false

    func player(for url: URL) -> AVQueuePlayer {
        if let player, self.url == url { return player }
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        self.player?.pause()
        self.player = player
        self.url = url
        if wantsPlaying { player.play() }
        return player
    }

    func setPlaying(_ playing: Bool) {
        wantsPlaying = playing
        if playing { player?.play() } else { player?.pause() }
    }
}
