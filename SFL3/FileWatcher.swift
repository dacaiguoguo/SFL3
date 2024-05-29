//
//  FileWatcher.swift
//  SFL3
//
//  Created by yanguo sun on 2024/5/29.
//
import SwiftUI
import Combine

import Foundation

class FileWatcher {
    private var fileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?

    init?(path: String, callback: @escaping () -> Void) {
        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor != -1 else {
            print("Failed to open file at path: \(path)")
            return nil
        }

        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: .all, queue: DispatchQueue.global())

        source?.setEventHandler(handler: {
            callback()
        })

        source?.setCancelHandler(handler: {
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        })

        source?.resume()
    }

    deinit {
        source?.cancel()
    }
}

import SwiftUI
import Combine
import CoreData

class FilePathsViewModel: ObservableObject {
    private var watcher: FileWatcher?
    private var cancellables = Set<AnyCancellable>()
    private weak var context: NSManagedObjectContext?

    init(context: NSManagedObjectContext) {
        self.context = context
        loadFilePaths()
    }

    func loadFilePaths() {
        if let userUrl = resolvedBookmark(key: "ApplicationRecentDocuments") {
            let filePath = userUrl.appendingPathComponent("com.apple.dt.xcode.sfl3").path
            watcher = FileWatcher(path: filePath) { [weak self] in
                self?.fileDidChange()
            }
        }
    }

    private func fileDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.reloadFilePaths()
        }
    }

    private func reloadFilePaths() {
        guard let context = context else { return }
        // 触发 NSFetchedResultsController 更新
        let fetchRequest: NSFetchRequest<FilePath> = FilePath.fetchRequest()
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \FilePath.isPinned, ascending: false),
            NSSortDescriptor(keyPath: \FilePath.createdAt, ascending: true)
        ]
        do {
            let results = try context.fetch(fetchRequest)
            results.forEach { filePath in
                context.refresh(filePath, mergeChanges: true)
            }
            self.objectWillChange.send()
        } catch {
            print("Failed to fetch file paths: \(error)")
        }
    }

    func openInFinder(_ path: String) {
        guard let url = URL(string: path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

