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
    @State private var counter = 0

    private func refreshUI() {
        self.filePaths.nsPredicate = NSPredicate(value: true)  // 触发重新查询和UI更新
        counter += 1
    }

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
            }.id(counter) // 强制重新创建视图
            .toolbar {
                ToolbarItem {
//                    Button(action: addSampleFilePath) {
//                        Label("Add Sample Path", systemImage: "plus")
//                    }
                    Button(action: deleteAllFilePaths) {
                        Label("Clear All", systemImage: "trash")
                    }
                }
            }
            Text("Select a path")
        }
        .onAppear {
            loadFilePaths()
        }
    }

    private func loadFilePaths2() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let relativePath = "Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/com.apple.dt.xcode.sfl3"
        let filePath = homeDirectory.appendingPathComponent(relativePath).path

        if let paths = readSflWithFile(filePath: filePath) {
            for path in paths {
                addFilePath(path)
            }
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
        // 检查是否已经存在相同的路径
        let fetchRequest: NSFetchRequest<FilePath> = FilePath.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "path == %@", path)
        
        do {
            let existingPaths = try viewContext.fetch(fetchRequest)
            if existingPaths.isEmpty {
                // 如果没有相同的路径，插入新的路径
                let newFilePath = FilePath(context: viewContext)
                newFilePath.path = path
                newFilePath.createdAt = Date()
                newFilePath.updatedAt = Date()
                newFilePath.isPinned = false

                try viewContext.save()
            } else {
                // 如果存在相同的路径，更新 updatedAt 字段
                let existingFilePath = existingPaths.first!
                existingFilePath.updatedAt = Date()
                try viewContext.save()
            }
        } catch {
            print("Failed to fetch file paths or save file path: \(error)")
        }
    }


    private func addSampleFilePath() {
        addFilePath("SamplePath/\(Date().timeIntervalSince1970)")
    }
    
    private func deleteAllFilePaths1() {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = FilePath.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)

        do {
            try viewContext.execute(deleteRequest)
            try viewContext.save()
            viewContext.reset()  // 重置上下文
        } catch {
            print("Error deleting all file paths: \(error)")
        }
    }

    private func deleteAllFilePaths() {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = FilePath.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)

        do {
            try viewContext.execute(deleteRequest)
            if let objects = try viewContext.fetch(fetchRequest) as? [NSManagedObject] {
                for object in objects {
                    viewContext.refresh(object, mergeChanges: false)
                }
            }
            try viewContext.save()
        } catch {
            print("Error deleting all file paths: \(error)")
        }
        
        refreshUI()
        print("filePaths:\(filePaths)")
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
