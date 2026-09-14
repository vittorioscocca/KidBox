//
//  KidBoxWordmark.swift
//  KidBox
//

import SwiftUI

/// Il marchio "KidBox" con "Box" arancione, come sulla landing e sulla web app
/// (`--text` / `--accent` di kidboxapp.com). `verbatim`: il nome non si traduce.
struct KidBoxWordmark: View {
    var size: CGFloat = 34

    @Environment(\.colorScheme) private var colorScheme

    private var kidColor: Color {
        colorScheme == .dark
        ? Color(red: 0xF6 / 255, green: 0xEF / 255, blue: 0xE6 / 255)
        : Color(red: 0x1C / 255, green: 0x10 / 255, blue: 0x08 / 255)
    }

    private var boxColor: Color {
        colorScheme == .dark
        ? Color(red: 0xF4 / 255, green: 0x99 / 255, blue: 0x5A / 255)
        : Color(red: 0xE8 / 255, green: 0x83 / 255, blue: 0x3A / 255)
    }

    /// AttributedString e non `Text + Text` (deprecato da iOS 26) né
    /// un'interpolazione, che finirebbe nel catalogo come chiave "%@%@".
    private var wordmark: AttributedString {
        var kid = AttributedString("Kid")
        kid.foregroundColor = kidColor
        var box = AttributedString("Box")
        box.foregroundColor = boxColor
        return kid + box
    }

    var body: some View {
        Text(wordmark)
            .font(.system(size: size, weight: .heavy))
            .kerning(-0.5)
            .accessibilityLabel(Text(verbatim: "KidBox"))
            .accessibilityAddTraits(.isHeader)
    }
}
