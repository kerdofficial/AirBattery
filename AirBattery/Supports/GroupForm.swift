//
//  GroupForm.swift
//  AirBattery
//
//  Created by apple on 2024/10/28.
//

import SwiftUI

struct HoverButton<Content: View>: View {
    var color: Color = .primary
    var secondaryColor: Color = .blue
    var action: () -> Void
    @ViewBuilder let label: () -> Content
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: {
            action()
        }, label: {
            label().foregroundColor(isHovered ? secondaryColor : color)
        })
        .buttonStyle(.plain)
        .onHover(perform: { isHovered = $0 })
    }
}

struct SForm<Content: View>: View {
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        Form { content() }
            .formStyle(.grouped)
    }
}

struct SGroupBox<Content: View>: View {
    var label: LocalizedStringKey? = nil
    var footer: LocalizedStringKey? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        Section {
            content()
        } header: {
            if let label { Text(label) }
        } footer: {
            if let footer {
                Text(footer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SRowLabel: View {
    var title: LocalizedStringKey
    var tips: LocalizedStringKey?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let tips {
                Text(tips)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SButton: View {
    var title: LocalizedStringKey
    var buttonTitle: LocalizedStringKey
    var tips: LocalizedStringKey?
    var action: () -> Void
    
    init(_ title: LocalizedStringKey, buttonTitle: LocalizedStringKey, tips: LocalizedStringKey? = nil, action: @escaping () -> Void) {
        self.title = title
        self.buttonTitle = buttonTitle
        self.tips = tips
        self.action = action
    }
    
    var body: some View {
        LabeledContent {
            Button(buttonTitle, action: action)
        } label: {
            SRowLabel(title: title, tips: tips)
        }
    }
}

struct SField: View {
    var title: LocalizedStringKey
    var placeholder: LocalizedStringKey
    var tips: LocalizedStringKey?
    @Binding var text: String
    var width: Double
    
    init(_ title: LocalizedStringKey, placeholder:LocalizedStringKey = "", tips: LocalizedStringKey? = nil, text: Binding<String>, width: Double = .infinity) {
        self.title = title
        self.placeholder = placeholder
        self.tips = tips
        self._text = text
        self.width = width
    }
    
    var body: some View {
        LabeledContent {
            TextField(title, text: $text, prompt: Text(placeholder))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: width)
        } label: {
            SRowLabel(title: title, tips: tips)
        }
    }
}

struct SPicker<T: Hashable, Content: View, Style: PickerStyle>: View {
    var title: LocalizedStringKey
    @Binding var selection: T
    var style: Style
    var tips: LocalizedStringKey?
    @ViewBuilder let content: () -> Content
    
    init(_ title: LocalizedStringKey, selection: Binding<T>, style: Style = .menu, tips: LocalizedStringKey? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self._selection = selection
        self.style = style
        self.tips = tips
        self.content = content
    }
    
    var body: some View {
        Picker(selection: $selection, content: content) {
            SRowLabel(title: title, tips: tips)
        }
        .pickerStyle(style)
    }
}

struct SToggle: View {
    var title: LocalizedStringKey
    @Binding var isOn: Bool
    var tips: LocalizedStringKey?
    
    init(_ title: LocalizedStringKey, isOn: Binding<Bool>, tips: LocalizedStringKey? = nil) {
        self.title = title
        self._isOn = isOn
        self.tips = tips
    }
    
    var body: some View {
        Toggle(isOn: $isOn) {
            SRowLabel(title: title, tips: tips)
        }
        .toggleStyle(.switch)
    }
}

struct SSteper: View {
    var title: LocalizedStringKey
    @Binding var value: Int
    var min: Int
    var max: Int
    var width: CGFloat
    var tips: LocalizedStringKey?
    
    init(_ title: LocalizedStringKey, value: Binding<Int>, min: Int = 0, max: Int = 100, width: CGFloat = 50, tips: LocalizedStringKey? = nil) {
        self.title = title
        self._value = value
        self.tips = tips
        self.width = width
        self.min = min
        self.max = max
    }
    
    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                TextField(title, value: $value, format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: width)
                    .onChange(of: value) { newValue in
                        if newValue > max { value = max }
                        if newValue < min { value = min }
                    }
                Stepper(title, value: $value, in: min...max)
                    .labelsHidden()
            }
        } label: {
            SRowLabel(title: title, tips: tips)
        }
    }
}
