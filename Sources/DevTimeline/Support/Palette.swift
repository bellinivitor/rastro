import AppKit
import SwiftUI

enum Palette {
    /// Tons categóricos validados para daltonismo (ordem fixa), com a variante para o modo escuro.
    /// O banco guarda o hex claro; a variante escura é escolhida na hora de desenhar.
    static let categorical: [(light: String, dark: String)] = [
        ("#2a78d6", "#3987e5"), // azul
        ("#eb6834", "#d95926"), // laranja
        ("#1baf7a", "#199e70"), // água
        ("#eda100", "#c98500"), // amarelo
        ("#e87ba4", "#d55181"), // magenta
        ("#008300", "#008300"), // verde
        ("#4a3aa7", "#9085e9"), // violeta
        ("#e34948", "#e66767"), // vermelho
    ]

    static var colors: [String] { categorical.map(\.light) }

    /// Cor de um projeto, adaptada ao modo claro/escuro.
    static func project(_ hex: String) -> Color {
        let pair = categorical.first { $0.light.caseInsensitiveCompare(hex) == .orderedSame }
        return dynamic(light: pair?.light ?? hex, dark: pair?.dark ?? hex)
    }

    /// Escala sequencial azul do heatmap: do menor para o maior volume.
    /// No escuro a ordem inverte (mais commits = mais claro, saltando do fundo).
    static let heat: [Color] = [
        dynamic(light: "#b7d3f6", dark: "#184f95"),
        dynamic(light: "#6da7ec", dark: "#256abf"),
        dynamic(light: "#2a78d6", dark: "#3987e5"),
        dynamic(light: "#1c5cab", dark: "#86b6ef"),
    ]

    static let heatEmpty = Color.primary.opacity(0.07)

    /// Cor das barras de ranking: uma só, o nome já identifica o projeto.
    static let bar = dynamic(light: "#2a78d6", dark: "#3987e5")

    static func dynamic(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x808080
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
