//
//  widgetBundle.swift
//  widget
//
//  Created by apple on 2024/2/18.
//

import WidgetKit
import SwiftUI

extension View {
    func widgetBackground(_ backgroundView: some View) -> some View {
        if #available(macOS 14.0, *) {
            return containerBackground(for: .widget) { backgroundView }
        } else {
            return background(backgroundView)
        }
    }
}

private struct WidgetFill: ViewModifier {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let color: Color

    func body(content: Content) -> some View {
        if renderingMode == .fullColor {
            content.foregroundColor(color).accentable()
        } else {
            content.foregroundColor(.white).accentable()
        }
    }
}

private struct WidgetTrack: ViewModifier {
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        content.opacity(renderingMode == .fullColor ? 0.15 : 0.3)
    }
}

private struct WidgetCapShadow: ViewModifier {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.shadow(color: renderingMode == .fullColor ? .black : .clear, radius: radius, x: 0, y: 0)
    }
}

extension View {
    @ViewBuilder
    func appWidgetBackground() -> some View {
        if #available(macOS 26.0, *) {
            containerBackground(.background, for: .widget)
        } else {
            widgetBackground(Color("WidgetBackground"))
        }
    }

    func widgetFill(_ color: Color) -> some View { modifier(WidgetFill(color: color)) }
    func widgetTrack() -> some View { modifier(WidgetTrack()) }
    func widgetCapShadow(_ radius: CGFloat) -> some View { modifier(WidgetCapShadow(radius: radius)) }

    @ViewBuilder
    func accentable() -> some View {
        if #available(macOS 14.0, *) { widgetAccentable() } else { self }
    }
}

extension Image {
    @ViewBuilder
    func iconAccentedRendering() -> some View {
        if #available(macOS 15.0, *) { widgetAccentedRenderingMode(.accentedDesaturated) } else { self }
    }
}

extension WidgetConfiguration {
    func disableContentMarginsIfNeeded() -> some WidgetConfiguration {
        if #available(macOS 12.0, *) {
            return self.contentMarginsDisabled()
        } else {
            return self
        }
    }
    
    func supportFamily() -> some WidgetConfiguration {
        if #available(macOS 14, *) {
            return self.supportedFamilies([.systemLarge, .systemMedium])
        } else {
            return self.supportedFamilies([.systemLarge, .systemMedium, .systemSmall])
        }
    }
}

@main
struct widgetBundle: WidgetBundle {
    var body: some Widget {
        widgets()
    }
    
    func widgets() -> some Widget {
        if #available(macOS 14, *) {
            return WidgetBundleBuilder.buildBlock(batteryWidget(), batteryWidget2New(), batteryWidget2(), batteryWidget3())
        } else {
            return WidgetBundleBuilder.buildBlock(batteryWidget(), batteryWidget2(), batteryWidget3())
        }
    }
}
