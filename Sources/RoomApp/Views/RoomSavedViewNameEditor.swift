import SwiftUI

struct RoomSavedViewNameEditor: View {
    let title: String
    let action: String
    let save: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide
    @FocusState private var nameFocused: Bool
    @State private var name: String
    @State private var failed = false

    init(title: String, action: String, name: String, save: @escaping (String) -> Bool) {
        self.title = title
        self.action = action
        self.save = save
        _name = State(initialValue: name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            Text(title).font(RoomTokens.Typography.title).accessibilityHeading(.h1)
            TextField("View name", text: $name)
                .focused($nameFocused)
                .accessibilityIdentifier("RoomSavedViewName")
            if failed {
                Text("Room couldn’t save this view.")
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
            HStack {
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action) {
                    if save(name) { dismiss() }
                    else { failed = true }
                }
                .roomPrimary(accent)
                .keyboardShortcut(.defaultAction)
                .disabled(RoomSavedView.cleanName(name) == nil)
            }
        }
        .padding(RoomTokens.Space.breath1)
        .frame(width: 360)
        .task { nameFocused = true }
        .onChange(of: hide.masksNow) { _, masked in if masked { name = "" } }
        .onChange(of: name) { _, _ in failed = false }
    }
}
