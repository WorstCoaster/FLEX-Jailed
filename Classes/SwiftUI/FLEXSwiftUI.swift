//
//  FLEXSwiftUI.swift
//  FLEX
//
//  SwiftUI surfaces for FLEX. The heavy lifting (heap scanning, instance
//  navigation, local URL mapping) stays in Objective-C and is reached through
//  FLEXSwiftBridge, so these views stay small and declarative.
//  Copyright (c) 2026 FLEX Team. All rights reserved.
//

import SwiftUI
import UIKit
import Foundation

#if canImport(FLEX)
import FLEX
#endif

// MARK: - Host

/// ObjC entry points. The trailing `With…` selector names match FLEXSwiftUIHost.h.
@objc(FLEXSwiftUIHost)
public final class FLEXSwiftUIHost: NSObject {
    @objc public static func heapObjectsController() -> UIViewController {
        let host = UIHostingController(rootView: HeapObjectsView(onSelect: { _ in }))
        host.view.backgroundColor = .clear
        let view = HeapObjectsView { className in
            guard let nav = host.navigationController else { return }
            FLEXSwiftBridge.pushInstances(ofClass: className, from: nav.topViewController ?? host)
        }
        host.rootView = view
        return host
    }

    @objc(localMapControllerWithPrefilledURL:completion:)
    public static func localMapController(prefilledURL: String?, completion: (() -> Void)?) -> UIViewController {
        let host = UIHostingController(rootView: LocalMapView(prefilledURL: prefilledURL, completion: completion))
        host.view.backgroundColor = .clear
        return host
    }
}

// MARK: - Heap Objects

/// Class-by-class live object counts, scanned off the main thread. A determinate
/// progress bar is shown while the scan runs so the screen never appears frozen.
struct HeapObjectsView: View {
    let onSelect: (String) -> Void

    @State private var names: [String] = []
    @State private var counts: [String: NSNumber] = [:]
    @State private var sizes: [String: NSNumber] = [:]
    @State private var isScanning = false
    @State private var scanFailed = false
    @State private var progress: Double = 0
    @State private var searchText = ""

    private struct Row: Identifiable {
        let id: String
        let name: String
        let count: Int
        let sizeText: String
    }

    private var rows: [Row] {
        let filtered = searchText.isEmpty
            ? names
            : names.filter { $0.localizedCaseInsensitiveContains(searchText) }
        let sorted = filtered.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        return sorted.map { name in
            let count = counts[name]?.intValue ?? 0
            let totalSize = count * (sizes[name]?.intValue ?? 0)
            return Row(
                id: name,
                name: name,
                count: count,
                sizeText: ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
            )
        }
    }

    var body: some View {
        Group {
            if isScanning {
                VStack(spacing: 20) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 320)
                    Text("Scanning heap…")
                        .font(.headline)
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if scanFailed {
                ContentUnavailableView(
                    "Scan Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The heap could not be scanned. Pull the list up to refresh.")
                )
            } else if rows.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(rows) { row in
                    Button {
                        onSelect(row.name)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                Text("\(row.count) instances · \(row.sizeText)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Filter classes"
                )
                .refreshable { await scan() }
            }
        }
        .navigationTitle("Heap Objects")
        .task { await scan() }
    }

    private func scan() async {
        guard !isScanning else { return }
        isScanning = true
        scanFailed = false
        progress = 0

        await withCheckedContinuation { continuation in
            FLEXSwiftBridge.beginHeapScan(withProgress: { value in
                progress = value
            }, completion: { names, counts, sizes in
                self.names = names
                self.counts = counts
                self.sizes = sizes
                self.isScanning = false
                continuation.resume()
            })
        }
    }
}

// MARK: - Map Local

/// A persisted "Map Local" rule: remote URL → local file, with an on/off switch.
fileprivate struct LocalMapping: Identifiable {
    let url: String
    let file: String
    let enabled: Bool
    var id: String { url }
}

fileprivate struct EditingMapping: Identifiable {
    let mapping: LocalMapping
    var id: String { mapping.url }
}

/// Editor for "Map Local" rules: remote URL → local file in the app sandbox.
struct LocalMapView: View {
    let prefilledURL: String?
    let completion: (() -> Void)?

    @State private var urlText = ""
    @State private var filePaths: [String] = []
    @State private var selectedFile: String?
    @State private var mappings: [LocalMapping] = []
    @State private var editing: EditingMapping?

    var body: some View {
        Form {
            Section {
                TextField("https://api.example.com/path", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                if filePaths.isEmpty {
                    Text("No files in the app's Documents directory yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Picker("Local file", selection: $selectedFile) {
                        ForEach(filePaths, id: \.self) { path in
                            Text((path as NSString).lastPathComponent).tag(path as String?)
                        }
                    }
                }

                Button {
                    createFile()
                } label: {
                    Label("Create new response file", systemImage: "plus")
                }

                Button("Add mapping") {
                    addMapping()
                }
                .disabled(urlText.isEmpty || selectedFile == nil)
            } header: {
                Text("Map URL to local file")
            } footer: {
                Text("Requests to the mapped URL are served from the local file instead of the network. Tap the pencil to edit the response in place.")
            }

            Section("Active mappings") {
                if mappings.isEmpty {
                    Text("No local mappings yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(mappings) { mapping in
                        HStack(spacing: 12) {
                            Toggle("", isOn: binding(for: mapping))
                                .labelsHidden()

                            Button {
                                openEditor(mapping)
                            } label: {
                                Image(systemName: "pencil")
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(mapping.url)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                Text((mapping.file as NSString).lastPathComponent)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .opacity(mapping.enabled ? 1 : 0.5)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                remove(mapping)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if !mappings.isEmpty {
                Section {
                    Button("Remove all mappings", role: .destructive) {
                        FLEXSwiftBridge.removeAllLocalMappings()
                        reload()
                    }
                }
            }
        }
        .navigationTitle("Map Local")
        .onAppear {
            urlText = prefilledURL ?? ""
            reload()
        }
        .sheet(item: $editing) { item in
            ResponseEditorView(mapping: item.mapping) {
                reload()
                completion?()
            }
        }
    }

    private func reload() {
        filePaths = FLEXSwiftBridge.localFilesInDocuments()
        if selectedFile == nil {
            selectedFile = filePaths.first
        }
        mappings = FLEXSwiftBridge.localMappings().map { dict in
            LocalMapping(
                url: (dict["url"] as? String) ?? "",
                file: (dict["file"] as? String) ?? "",
                enabled: (dict["enabled"] as? NSNumber)?.boolValue ?? true
            )
        }
    }

    private func binding(for mapping: LocalMapping) -> Binding<Bool> {
        Binding(
            get: {
                self.mappings.first(where: { $0.url == mapping.url })?.enabled ?? mapping.enabled
            },
            set: { newValue in
                FLEXSwiftBridge.setEnabled(newValue, forLocalMappingURL: mapping.url)
                completion?()
                reload()
            }
        )
    }

    private func createFile() {
        if let path = FLEXSwiftBridge.createLocalFile(withBaseName: "response.json") {
            reload()
            selectedFile = path
        }
    }

    private func addMapping() {
        guard let file = selectedFile, !urlText.isEmpty else { return }
        FLEXSwiftBridge.setLocalMapping(forURL: urlText, toFile: file)
        reload()
        completion?()
        openEditor(LocalMapping(url: urlText, file: file, enabled: true))
    }

    private func openEditor(_ mapping: LocalMapping) {
        editing = EditingMapping(mapping: mapping)
    }

    private func remove(_ mapping: LocalMapping) {
        FLEXSwiftBridge.removeLocalMapping(forURL: mapping.url)
        completion?()
        reload()
    }
}

/// Full-screen UTF-8 text editor for a Map Local response file.
fileprivate struct ResponseEditorView: View {
    let mapping: LocalMapping
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading response...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                }
            }
            .navigationTitle((mapping.file as NSString).lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        FLEXSwiftBridge.writeContents(text, toFileAtPath: mapping.file)
                        onDone()
                        dismiss()
                    }
                    .disabled(isLoading)
                }
            }
            .onAppear {
                text = FLEXSwiftBridge.fileContents(atPath: mapping.file) ?? ""
                isLoading = false
            }
        }
    }
}
