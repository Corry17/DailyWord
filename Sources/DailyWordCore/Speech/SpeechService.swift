import AVFoundation

/// 系统 TTS 发音封装（离线可用）
public final class SpeechService {
    public static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()

    public enum Accent: String {
        case american = "en-US"
        case british = "en-GB"
    }

    public var accent: Accent = .american

    public func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: accent.rawValue)
        utterance.rate = 0.45
        synthesizer.speak(utterance)
    }
}
