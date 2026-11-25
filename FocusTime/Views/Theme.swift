//
//  Theme.swift
//  FocusTime
//
//  Created by hamilton jafet vasquez chiquillo on 19/10/26.
//

import SwiftUI

enum Theme {
    static let primary = Color(red: 0.20, green: 0.65, blue: 0.45)
    static let primaryDark = Color(red: 0.10, green: 0.42, blue: 0.32)
    static let accent = Color(red: 0.98, green: 0.76, blue: 0.25)
    static let cardBackground = Color(.secondarySystemBackground)

    static let primaryGradient = LinearGradient(
        colors: [primary, primaryDark],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let focusBackground = LinearGradient(
        colors: [Color(red: 0.07, green: 0.10, blue: 0.14),
                 Color(red: 0.10, green: 0.22, blue: 0.22)],
        startPoint: .top, endPoint: .bottom)
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.cardBackground)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

/// Anillo de progreso. progress va de 0 a 1.
struct RingProgress: View {
    let progress: Double
    var lineWidth: CGFloat = 14
    var color: Color = Theme.primary

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: progress)
        }
    }
}

struct StatTile: View {
    let icon: String
    let value: String
    let title: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }
}

struct InfoRow: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(Circle().fill(tint.opacity(0.15)))
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.headline)
                .monospacedDigit()
        }
    }
}
