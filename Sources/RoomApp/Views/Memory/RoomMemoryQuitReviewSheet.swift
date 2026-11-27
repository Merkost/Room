#if !ROOM_APP_STORE
import RoomCore
import SwiftUI

struct MemoryQuitReviewSheet: View {
    let review: MemoryQuitReview
    let isApplying: Bool
    let cancel: () -> Void
    let request: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("A little breathing room.").font(RoomType.heading(24))
                    Text("Review \(review.count) \(review.count == 1 ? "app" : "apps") before requesting a normal quit.")
                        .font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "power.circle").font(.system(size: 31, weight: .light)).foregroundStyle(.secondary) // design-gate: allow symbol size
            }
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(review.applications) { application in
                        HStack(spacing: 12) {
                            if let icon = application.icon { Image(nsImage: icon).resizable().frame(width: 26, height: 26) }
                            Text(application.name).font(RoomTokens.Typography.body)
                            Spacer()
                            if let resident = application.residentBytes {
                                Text("≈ \(RoomFormat.memory(resident))").font(RoomTokens.Typography.body).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 230)
            VStack(alignment: .leading, spacing: 8) {
                if review.residentBytes > 0 {
                    Text("About \(RoomFormat.memory(review.residentBytes)) resident in this sample")
                        .font(RoomTokens.Typography.bodyStrong)
                }
                if review.unmeasuredCount > 0 {
                    Text("\(review.unmeasuredCount) \(review.unmeasuredCount == 1 ? "app is" : "apps are") outside the current process sample.")
                        .font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                }
                Text("Apps may ask you to save unsaved work or cancel. Nothing is forced to close. Resident sizes include shared pages and exclude helpers; they are not a promise of freed RAM.")
                    .font(RoomTokens.Typography.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                if isApplying { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction).disabled(isApplying)
                Button("Request Quit", action: request)
                    .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction).disabled(isApplying)
            }
        }
        .padding(28).frame(width: 500)
    }
}
#endif
