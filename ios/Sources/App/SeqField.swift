import SwiftUI
import CuelistCompilerKit

/// Tappable numeric sequence field. Replaces the seq Stepper — type a value,
/// committed on focus-loss/return, clamped to 1...9999.
struct SeqField: View {
    @Binding var sequence: Int
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text("Seq").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textDim)
            TextField("1", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.text)
                .frame(width: 54)
                .padding(.vertical, 5)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
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
