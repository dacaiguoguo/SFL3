//
//  ContentView.swift
//  SFL3
//
//  Created by yanguo sun on 2024/5/28.
//

import SwiftUI
import CoreData

import Foundation

func readSflWithFile(filePath: String) -> [String]? {
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: filePath) {
        return nil
    }
    
    let fileUrl = URL(fileURLWithPath: filePath)
    do {
        let data = try Data(contentsOf: fileUrl, options: .mappedIfSafe)
        return readSflWithData(data: data)
    } catch {
        print(error.localizedDescription)
        return nil
    }
}

func readSflWithData(data: Data) -> [String]? {
    if data.isEmpty {
        return nil
    }
    
    var recentList: [Any]?
    do {
        if let recentListInfo = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? [String: Any] {
            recentList = recentListInfo["items"] as? [Any]
        }
    } catch {
        print("Exception during unarchiving: \(error)")
        return nil
    }
    
    guard let items = recentList else {
        return nil
    }
    
    var mutArray = [String]()
    
    for item in items {
        var resolvedUrl: URL?
        
        if let dict = item as? [String: Any], let bookmark = dict["Bookmark"] as? Data {
            do {
                var isStale = false
                resolvedUrl = try URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale)
            } catch {
                print("Error resolving bookmark: \(error)")
                continue
            }
        }
        
        if let urlPath = resolvedUrl?.path {
            mutArray.append(urlPath)
        }
    }
    
    return mutArray
}


import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        entity: FilePath.entity(),
        sortDescriptors: [
            NSSortDescriptor(keyPath: \FilePath.isPinned, ascending: false), // Pinned items first
            NSSortDescriptor(keyPath: \FilePath.createdAt, ascending: true)   // Then by creation time
        ],
        animation: .default)
    private var filePaths: FetchedResults<FilePath>

    var body: some View {
        NavigationView {
            List {
                ForEach(filePaths) { filePath in
                    HStack {
                        Text(filePath.path ?? "Unknown Path")
                        Spacer()
                        Button(action: {
                            openInFinder(filePath.path)
                        }) {
                            Image(systemName: "folder")
                        }
                        Button(action: {
                            moveToTop(filePath)
                        }) {
                            Image(systemName: "pin.fill")
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem {
                    Button(action: addSampleFilePath) {
                        Label("Add Sample Path", systemImage: "plus")
                    }
                }
            }
            Text("Select a path")
        }
        .onAppear {
            loadFilePaths()
        }
    }
    
    
    private func loadFilePaths() {
        let filePath = Bundle.main.path(forResource: "com.apple.dt.xcode", ofType: "sfl3") ?? ""
        if let paths = readSflWithFile(filePath: filePath) {
            for path in paths {
                addFilePath(path)
            }
        }
    }

    private func openInFinder(_ path: String?) {
        guard let path = path, let url = URL(fileURLWithPath: path).deletingLastPathComponent() as URL? else { return }
        let ret = NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
        print("open result:\(ret)")
    }

    private func moveToTop(_ filePath: FilePath) {
        viewContext.perform {
            filePath.isPinned = true // Mark as pinned
            do {
                try viewContext.save()
            } catch {
                print("Failed to move to top: \(error)")
            }
        }
    }

    private func addFilePath(_ path: String) {
        let newFilePath = FilePath(context: viewContext)
        newFilePath.path = path
        newFilePath.createdAt = Date()
        newFilePath.updatedAt = Date()
        newFilePath.isPinned = false

        do {
            try viewContext.save()
        } catch {
            print("Failed to save file path: \(error)")
        }
    }

    private func addSampleFilePath() {
        addFilePath("SamplePath/\(Date().timeIntervalSince1970)")
    }
}


private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
