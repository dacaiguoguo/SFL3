//
//  FilePathsViewModel.swift
//  SFL3
//
//  Created by yanguo sun on 2024/5/30.
//

import Foundation
import SwiftUI
import Combine
import CoreData

extension Notification.Name {
    static let filePathsDidUpdate = Notification.Name("filePathsDidUpdate")
}


class FilePathsViewModel: ObservableObject {
    private var watcher: FileWatcher?
    private var cancellables = Set<AnyCancellable>()
    @Published var userInput: String = ""

    init() {
        watchFilePaths()
    }

    func watchFilePaths() {
        if let userUrl = resolvedBookmark(key: "ApplicationRecentDocuments") {
            watcher = FileWatcher(path: userUrl.path) { [weak self] in
                self?.fileDidChange()
            }
        }
    }

    private func fileDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .filePathsDidUpdate, object: nil)
        }
    }
}

import SwiftUI

class IconFinder: ObservableObject {
    @Published var icons: [URL] = []

    func findAppIcon(in filePath: String) {
        DispatchQueue.global(qos: .default).async {
            let fileManager = FileManager.default
            let workPathURL = URL(fileURLWithPath: filePath)
            let enumerator = fileManager.enumerator(at: workPathURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)

            var appiconsetURL: URL?
            while let fileURL = enumerator?.nextObject() as? URL {
                if fileURL.pathExtension == "appiconset" {
                    appiconsetURL = fileURL
                    break // Stop after finding the first appiconset folder
                }
            }

            var foundIcon = false // Control flag to break the loop

            if let appiconset = appiconsetURL {
                let iconEnumerator = fileManager.enumerator(at: appiconset, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                while let iconFileURL = iconEnumerator?.nextObject() as? URL, !foundIcon { // Check the flag
                    if let _ = try? Data(contentsOf: iconFileURL) {
                        DispatchQueue.main.async {
                            self.icons.append(iconFileURL)
                        }
                        foundIcon = true // Set the flag to true to break the loop
                    }
                }
            }
        }
    }
}
