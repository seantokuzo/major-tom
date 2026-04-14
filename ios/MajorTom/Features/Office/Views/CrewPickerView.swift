import SwiftUI

// MARK: - Crew Picker View

/// Lets the user set their preferred crew order.
/// First 6 are the active idle crew. Additional picks become the overflow priority pool.
/// Drag selected crew to reorder, tap available crew to add, swipe-to-delete to remove.
struct CrewPickerView: View {
    let crewRoster: CrewRoster
    let onDismiss: () -> Void

    @State private var selectedHumans: [CharacterType] = []
    @State private var availableHumans: [CharacterType] = []

    private static let maxIdle = OfficeViewModel.maxIdleHumans

    var body: some View {
        NavigationStack {
            List {
                // Selected crew — drag to reorder
                Section {
                    ForEach(selectedHumans, id: \.rawValue) { charType in
                        crewRow(charType, index: selectedHumans.firstIndex(of: charType))
                    }
                    .onMove { from, to in
                        selectedHumans.move(fromOffsets: from, toOffset: to)
                    }
                    .onDelete { offsets in
                        let removed = offsets.map { selectedHumans[$0] }
                        selectedHumans.remove(atOffsets: offsets)
                        availableHumans.append(contentsOf: removed)
                        availableHumans.sort { $0.rawValue < $1.rawValue }
                    }
                } header: {
                    Text("Preferred Crew (\(selectedHumans.count))")
                } footer: {
                    if selectedHumans.isEmpty {
                        Text("Tap crew below to add them. First \(Self.maxIdle) are your active idle crew.")
                    } else if selectedHumans.count <= Self.maxIdle {
                        Text("First \(Self.maxIdle) are active. Remaining \(Self.maxIdle - selectedHumans.count) slot\(Self.maxIdle - selectedHumans.count == 1 ? "" : "s") filled randomly.")
                    } else {
                        Text("First \(Self.maxIdle) are active idle crew. #\(Self.maxIdle + 1)+ are overflow priority.")
                    }
                }

                // Available (unselected) crew
                Section("Available Crew") {
                    ForEach(availableHumans, id: \.rawValue) { charType in
                        Button {
                            withAnimation {
                                availableHumans.removeAll { $0 == charType }
                                selectedHumans.append(charType)
                            }
                        } label: {
                            HStack {
                                characterPreview(charType)
                                Text(CharacterCatalog.config(for: charType).displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Crew")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        selectedHumans = []
                        availableHumans = allHumans
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        crewRoster.setPreferredOrder(selectedHumans)
                        onDismiss()
                    }
                    .bold()
                }
            }
            .environment(\.editMode, .constant(.active))
        }
        .onAppear {
            // Extra safety: filter to humans + dedupe even though CrewRoster already
            // sanitizes on load. ForEach(id: \.rawValue) crashes on duplicates.
            var seen = Set<CharacterType>()
            selectedHumans = crewRoster.preferredOrder.filter {
                !$0.isDog && seen.insert($0).inserted
            }
            let selected = Set(selectedHumans)
            availableHumans = allHumans.filter { !selected.contains($0) }
        }
    }

    // MARK: - Helpers

    private var allHumans: [CharacterType] {
        CharacterType.allCases.filter { !$0.isDog }.sorted { $0.rawValue < $1.rawValue }
    }

    private func crewRow(_ charType: CharacterType, index: Int?) -> some View {
        HStack {
            characterPreview(charType)

            VStack(alignment: .leading, spacing: 2) {
                Text(CharacterCatalog.config(for: charType).displayName)
                    .font(.body)

                if let idx = index {
                    if idx < Self.maxIdle {
                        Text("Active crew #\(idx + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Overflow #\(idx - Self.maxIdle + 1)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()
        }
    }

    /// Small sprite preview using the front-facing texture.
    @ViewBuilder
    private func characterPreview(_ charType: CharacterType) -> some View {
        Image(charType.rawValue + "_front")
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}
