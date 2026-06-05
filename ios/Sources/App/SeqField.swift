import SwiftUI
import CuelistCompilerKit

/// Tappable numeric sequence field. Replaces the seq Stepper — type a value,
/// committed on focus-loss/return, clamped to 1...9999.
struct SeqField: View {
    @Binding var sequence: Int
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("Seq").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
            TextField("1", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.text)
                .frame(width: 70)
                .padding(.vertical, 9)
                .background(Theme.surface3, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .strokeBorder(Theme.borderStrong, lineWidth: 1))
                .focused($focused)
        }
        .onAppear { text = String(sequence) }
        .onChange(of: sequence) { _, new in if !focused { text = String(new) } }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }

    private func commit() {
        let parsed = Int(text.filter(\.isNumber)) ?? sequence
        let clamped = min(9999, max(1, parsed))
        sequence = clamped
        text = String(clamped)
    }
}
