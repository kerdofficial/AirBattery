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

extension View {
    @ViewBuilder
    func appWidgetBackground() -> some View {
        if #available(macOS 26.0, *), AirBatteryModel.readWidgetBackground() == "translucent" {
            containerBackground(.background, for: .widget)
        } else {
            widgetBackground(Color("WidgetBackground"))
        }
    }

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
