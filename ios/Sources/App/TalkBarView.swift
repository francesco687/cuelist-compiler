import SwiftUI
import CuelistCompilerKit

/// Full-width voice bar (kept for the Notes sheet's big mic). The Author tab now
/// uses VoiceButton directly inside BottomCluster.
struct TalkBarView: View {
    var body: some View {
        VoiceButton(fullWidth: true)
            .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 4)
    }
}
