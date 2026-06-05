import SwiftUI

/// A −/value/+ control bound to a String (fade/delay are Strings in the model).
/// Buttons bump by 0.5 and clamp at 0; the field also accepts direct decimal entry.
struct StepperField: View {
    let label: String
    @Binding var value: String
    var placeholder: String = ""
    var tint: Color = Theme.accentSolid

    private func bump(_ delta: Double) {
        let base = Double(value) ?? Double(placeholder) ?? 0
        let next = max(0, base + delta)
        value = next == next.rounded() ? String(Int(next)) : String(next)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textDim)
            HStack(spacing: 0) {
                Button { bump(-0.5) } label: {
                    Image(systemName: "minus").frame(width: 30, height: 30)
                }.buttonStyle(.plain).foregroundStyle(Theme.accentSolid)
                TextField(placeholder, text: $value)
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(tint)
                    .frame(width: 46)
                Button { bump(0.5) } label: {
                    Image(systemName: "plus").frame(width: 30, height: 30)
                }.buttonStyle(.plain).foregroundStyle(Theme.accentSolid)
            }
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.borderStrong, lineWidth: 1))
        }
    }
}
