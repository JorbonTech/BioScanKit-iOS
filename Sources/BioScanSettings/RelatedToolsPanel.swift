import SwiftUI
import UIKit
import BioScanDesign

// MARK: - Palette

/// The six colours the panel needs. Hosts pass their own so the panel sits in
/// the host's result-page palette instead of importing a whole theme.
public struct RelatedToolsPalette: Sendable {
    public let panelBackground: AdaptiveColor
    public let panelBorder: AdaptiveColor
    public let rowBackground: AdaptiveColor
    /// The retake row sits on a panel that is sometimes tinted (Mr.Mushroom's
    /// caution panel is coral), so it cannot reuse the panel fill.
    public let retakeBackground: AdaptiveColor
    public let accent: Color
    public let primaryText: AdaptiveColor
    public let secondaryText: AdaptiveColor
    public let tertiaryText: AdaptiveColor

    public init(
        panelBackground: AdaptiveColor,
        panelBorder: AdaptiveColor,
        rowBackground: AdaptiveColor,
        retakeBackground: AdaptiveColor,
        accent: Color,
        primaryText: AdaptiveColor,
        secondaryText: AdaptiveColor,
        tertiaryText: AdaptiveColor
    ) {
        self.panelBackground = panelBackground
        self.panelBorder = panelBorder
        self.rowBackground = rowBackground
        self.retakeBackground = retakeBackground
        self.accent = accent
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.tertiaryText = tertiaryText
    }
}

public extension RelatedToolsPalette {
    /// Matches the iNature result page's `database*` panel tokens.
    static let result = RelatedToolsPalette(
        panelBackground: AdaptiveColor(
            light: Color(red: 0.98, green: 0.99, blue: 1.00),
            dark: Color(red: 0.10, green: 0.13, blue: 0.17)
        ),
        panelBorder: AdaptiveColor(
            light: Color(red: 0.90, green: 0.94, blue: 0.98),
            dark: Color(red: 0.20, green: 0.26, blue: 0.34)
        ),
        rowBackground: AdaptiveColor(
            light: Color(red: 0.88, green: 0.94, blue: 1.00),
            dark: Color(red: 0.16, green: 0.25, blue: 0.36)
        ),
        retakeBackground: AdaptiveColor(
            light: Color(red: 0.98, green: 0.99, blue: 1.00),
            dark: Color(red: 0.10, green: 0.13, blue: 0.17)
        ),
        accent: Color(red: 0.28, green: 0.46, blue: 0.74),
        primaryText: AdaptiveColor(
            light: Color(red: 0.05, green: 0.10, blue: 0.20),
            dark: Color.white.opacity(0.94)
        ),
        secondaryText: AdaptiveColor(
            light: Color(red: 0.34, green: 0.41, blue: 0.52),
            dark: Color(red: 0.58, green: 0.64, blue: 0.74)
        ),
        tertiaryText: AdaptiveColor(
            light: Color(red: 0.44, green: 0.50, blue: 0.60),
            dark: Color(red: 0.51, green: 0.58, blue: 0.67)
        )
    )
}

// MARK: - Panel

/// One container, two variants, shared by every BioScan app.
///
/// - `.related` is a footnote to a trustworthy result and sits after the
///   species overview: an eyebrow plus one or two action rows.
/// - `.caution` qualifies an untrustworthy result and sits before the species
///   header: the same rows plus a question mark, a headline and a retake action.
public struct RelatedToolsPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var didAppear = false

    /// Rows grow with the reader's text size; icons stay put. A 2× app icon
    /// would eat the label at accessibility sizes without adding legibility.
    @ScaledMetric(relativeTo: .footnote) private var rowHeight: CGFloat = 56

    private let iconSize: CGFloat = 32
    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }
    private var rowLineLimit: Int { isAccessibilitySize ? 2 : 1 }

    private let recommendation: RelatedToolsRecommendation
    private let palette: RelatedToolsPalette
    private let cornerRadius: CGFloat
    private let rowCornerRadius: CGFloat
    private let cautionIcon: String
    private let cautionHeadline: String?
    private let cautionDetail: String?
    private let onOpen: (RelatedTool) -> Void
    private let onRetake: (() -> Void)?
    private let onShown: ((RelatedToolsRecommendation) -> Void)?
    private let exposure: RelatedToolsExposure?
    private let contextID: String?
    private let bundle: Bundle

    /// - Parameters:
    ///   - cornerRadius: the host's card radius. iNature's result page uses 16;
    ///     Mr.Fish builds on 8 and a 16 here would break its geometry.
    ///   - rowCornerRadius: the host's row radius, usually a step tighter than
    ///     the card.
    ///   - cautionIcon: an SF Symbol. `questionmark` says "unsure",
    ///     `exclamationmark` says "dangerous" — Mr.Mushroom passes the latter
    ///     because its low-confidence state is a safety message, not a doubt.
    ///   - onShown: called once when the panel appears, for exposure tracking.
    ///     Hosts own their analytics, so each passes its own one-liner.
    ///   - exposure: where the weekly cap is recorded. Pass `nil` to opt a host
    ///     out of capping entirely.
    ///   - contextID: the result being shown. Re-rendering the same screen must
    ///     not spend another allowance, so pass the result or attempt id.
    public init(
        recommendation: RelatedToolsRecommendation,
        palette: RelatedToolsPalette = .result,
        cornerRadius: CGFloat = 16,
        rowCornerRadius: CGFloat = 12,
        cautionIcon: String = "questionmark",
        cautionHeadline: String? = nil,
        cautionDetail: String? = nil,
        bundle: Bundle = .main,
        onOpen: @escaping (RelatedTool) -> Void,
        onRetake: (() -> Void)? = nil,
        contextID: String? = nil,
        onShown: ((RelatedToolsRecommendation) -> Void)? = nil,
        exposure: RelatedToolsExposure? = .shared
    ) {
        self.recommendation = recommendation
        self.palette = palette
        self.cornerRadius = cornerRadius
        self.rowCornerRadius = rowCornerRadius
        self.cautionIcon = cautionIcon
        self.cautionHeadline = cautionHeadline
        self.cautionDetail = cautionDetail
        self.bundle = bundle
        self.onOpen = onOpen
        self.onRetake = onRetake
        self.onShown = onShown
        self.exposure = exposure
        self.contextID = contextID
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            VStack(spacing: 8) {
                ForEach(recommendation.tools) { tool in
                    Button {
                        onOpen(tool)
                    } label: {
                        toolRow(tool)
                    }
                    .buttonStyle(RelatedToolRowButtonStyle())
                }

                if recommendation.variant == .caution, let onRetake {
                    Button(action: onRetake) {
                        retakeRow
                    }
                    .buttonStyle(RelatedToolRowButtonStyle())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(palette.panelBackground.resolve(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(palette.panelBorder.resolve(for: colorScheme), lineWidth: 1)
        )
        .onAppear {
            guard !didAppear else { return }
            didAppear = true
            exposure?.record(recommendation.tools.map(\.id), contextID: contextID)
            onShown?(recommendation)
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        if recommendation.variant == .caution {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(palette.rowBackground.resolve(for: colorScheme))
                    Image(systemName: cautionIcon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.accent)
                }
                .frame(width: iconSize, height: iconSize)

                VStack(alignment: .leading, spacing: 5) {
                    eyebrow(cautionEyebrow)

                    Text(cautionHeadline ?? defaultCautionHeadline)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(palette.primaryText.resolve(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(cautionDetail ?? defaultCautionDetail)
                        .font(.system(.footnote, design: .rounded).weight(.medium))
                        .foregroundStyle(palette.secondaryText.resolve(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            eyebrow(BioScanSettingsL10n.string("related.eyebrow"))
        }
    }

    private var cautionEyebrow: String {
        // String(format:) keeps translators free to move the token.
        String(
            format: BioScanSettingsL10n.string("related.lowConfidence.eyebrowFormat"),
            "\(Int((recommendation.confidence * 100).rounded()))%"
        )
    }

    private var defaultCautionHeadline: String {
        BioScanSettingsL10n.string("related.lowConfidence.title")
    }

    private var defaultCautionDetail: String {
        BioScanSettingsL10n.string("related.lowConfidence.detail")
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(.caption2, design: .monospaced).weight(.bold))
            .tracking(isAccessibilitySize ? 0 : 1.4)
            .lineLimit(2)
            .foregroundStyle(palette.tertiaryText.resolve(for: colorScheme))
    }

    // MARK: Rows

    private func toolRow(_ tool: RelatedTool) -> some View {
        HStack(spacing: 12) {
            appIcon(name: tool.imageName, fallback: tool.name)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.action)
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(palette.primaryText.resolve(for: colorScheme))
                    .lineLimit(rowLineLimit)
                    .minimumScaleFactor(0.8)
                Text(tool.detail)
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(palette.secondaryText.resolve(for: colorScheme))
                    .lineLimit(rowLineLimit)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.up.forward")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isAccessibilitySize ? 10 : 0)
        .frame(minHeight: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                .fill(palette.rowBackground.resolve(for: colorScheme))
        )
        .contentShape(.rect(cornerRadius: rowCornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(tool.action), \(tool.detail)"))
        .accessibilityAddTraits(.isButton)
    }

    private var retakeRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(palette.panelBorder.resolve(for: colorScheme).opacity(0.55))
                Image(systemName: "viewfinder")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.secondaryText.resolve(for: colorScheme))
            }
            .frame(width: iconSize, height: iconSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(BioScanSettingsL10n.string("related.retake.action"))
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(palette.primaryText.resolve(for: colorScheme))
                    .lineLimit(rowLineLimit)
                Text(BioScanSettingsL10n.string("related.retake.detail"))
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(palette.secondaryText.resolve(for: colorScheme))
                    .lineLimit(rowLineLimit)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.tertiaryText.resolve(for: colorScheme))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isAccessibilitySize ? 10 : 0)
        .frame(minHeight: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                .fill(palette.retakeBackground.resolve(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                .stroke(palette.panelBorder.resolve(for: colorScheme), lineWidth: 1)
        )
        .contentShape(.rect(cornerRadius: rowCornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(BioScanSettingsL10n.string("related.retake.action")), \(BioScanSettingsL10n.string("related.retake.detail"))"))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func appIcon(name: String?, fallback: String) -> some View {
        Group {
            if let name, let image = UIImage(named: name, in: bundle, compatibleWith: nil) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // A missing asset should still read as an app, not as a gap.
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(palette.accent.opacity(0.16))
                    Text(String(fallback.prefix(1)).uppercased())
                        .font(.system(size: iconSize * 0.44, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.accent)
                }
            }
        }
        .frame(width: iconSize, height: iconSize)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// Rows respond to touch: without it the panel reads as a static card.
private struct RelatedToolRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
