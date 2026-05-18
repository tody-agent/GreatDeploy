import SwiftUI

struct MCPRegistryView: View {
    @EnvironmentObject var bundleStore: MCPBundleStore
    @State private var client = SmitheryClient()
    @State private var searchText = ""
    @State private var entries: [RegistryEntry] = []
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    var activeBundle: MCPBundle? {
        bundleStore.activeBundle
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            Group {
                if isLoading {
                    ProgressView("Searching registry...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if entries.isEmpty {
                    emptyStateView
                } else {
                    registryListView
                }
            }
        }
        .task { await loadEntries() }
        .onChange(of: searchText) { _ in
            Task { await debounceSearch() }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private var headerView: some View {
        HStack {
            Text("Registry")
                .font(.title2)
                .fontWeight(.bold)
            Spacer()
            TextField("Search registry...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
        }
        .padding()
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No servers found")
                .font(.headline)
                .foregroundStyle(.secondary)
            if !searchText.isEmpty {
                Text("Try a different search term")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var registryListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    registryRow(entry)
                    if entry.id != entries.last?.id {
                        Divider().padding(.leading, 60)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func registryRow(_ entry: RegistryEntry) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 16))
                    .foregroundStyle(.purple)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayName ?? entry.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let desc = entry.description {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    if let count = entry.installCount {
                        Text("\(count) installs")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let tags = entry.tags, !tags.isEmpty {
                        ForEach(tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(3)
                        }
                    }
                }
            }

            Spacer()

            Button(action: { install(entry) }) {
                Label("Install", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .disabled(activeBundle == nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func loadEntries() async {
        isLoading = true
        defer { isLoading = false }

        if searchText.isEmpty {
            entries = await client.getPopular()
        } else {
            entries = await client.search(query: searchText)
        }
    }

    @State private var searchTask: Task<Void, Never>?

    private func debounceSearch() async {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !Task.isCancelled {
                await loadEntries()
            }
        }
    }

    private func install(_ entry: RegistryEntry) {
        guard let bundle = activeBundle else { return }

        let server = entry.toServerDefinition()

        do {
            try bundleStore.addServer(server, to: bundle.id)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
