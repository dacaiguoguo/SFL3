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
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        if let recentListInfo = unarchiver.decodeObject(of: [NSDictionary.self, NSArray.self], forKey: NSKeyedArchiveRootObjectKey) as? [String: Any] {
            recentList = recentListInfo["items"] as? [Any]
        }
        unarchiver.finishDecoding()
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
                        Button(action: deleteAllFilePaths) {
                            Label("Clear All", systemImage: "trash")
                        }
                    }
                    ToolbarItem {
                        Button(action: requestAgent) {
                            Label("Give Auth", systemImage: "plus.circle")
                        }
                    }
                    ToolbarItem {
                        Button(action: requestDev) {
                            Label("Give Dev", systemImage: "plus.diamond")
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
        if let userUrl = resolvedBookmark(key: "ApplicationRecentDocuments") {
            
            if let paths = readSflWithFile(filePath: userUrl.appendingPathComponent("com.apple.dt.xcode.sfl3").path) {
                for path in paths {
                    addFilePath(path)
                }
            }
        }
        
        let _ = resolvedBookmark(key: "dev")
//        let filePath = Bundle.main.path(forResource: "com.apple.dt.xcode", ofType: "sfl3") ?? ""
//        if let paths = readSflWithFile(filePath: filePath) {
//            for path in paths {
//                addFilePath(path)
//            }
//        }
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
    
    private func requestAgent() {
        let openPanel = NSOpenPanel()
        openPanel.prompt = "Grant Access"
        openPanel.message = "Please grant access to the folder"
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = false
        // 尝试设置一个默认目录
        let path = NSString(string: "~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments").expandingTildeInPath
        openPanel.directoryURL = URL(fileURLWithPath: path)
        openPanel.begin { (result) -> Void in
            if result == .OK, let userUrl = openPanel.url {
                let accessGranted = userUrl.startAccessingSecurityScopedResource()
                if accessGranted {
                    saveBookmarkData(from: userUrl)
                    let selectedPath = userUrl.appendingPathComponent("com.apple.dt.xcode.sfl3")
                    if let paths = readSflWithFile(filePath: selectedPath.path) {
                        for path in paths {
                            addFilePath(path)
                        }
                    }
                } else {
                    print("Failed to access the resource.")
                }
                print("At bookmark \(accessGranted).")
            }
        }
    }
    
    private func requestDev() {
        let openPanel = NSOpenPanel()
        openPanel.prompt = "Grant Access"
        openPanel.message = "Please grant access to the folder"
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = false
        // 尝试设置一个默认目录
        let path = NSString(string: "~/Developer").expandingTildeInPath
        openPanel.directoryURL = URL(fileURLWithPath: path)
        openPanel.begin { (result) -> Void in
            if result == .OK, let userUrl = openPanel.url {
                let accessGranted = userUrl.startAccessingSecurityScopedResource()
                if accessGranted {
                    saveBookmarkData(from: userUrl, key: "dev")
                } else {
                    print("Failed to access the resource.")
                }
                print("At bookmark \(accessGranted).")
            }
        }

    }

    func saveBookmarkData(from docURL: URL, key: String = "ApplicationRecentDocuments") {
        do {
            // 创建只读访问的安全书签数据
            let bookmarkData = try docURL.bookmarkData(options: .securityScopeAllowOnlyReadAccess, includingResourceValuesForKeys: nil, relativeTo: nil)
            
            // 将书签数据保存到 UserDefaults
            UserDefaults.standard.set(bookmarkData, forKey: key)
        } catch {
            print("Failed to create bookmark data: \(error)")
        }
    }

    func resolvedBookmark(key: String) -> URL? {
        let userDefaults = UserDefaults.standard
        guard let bookmarkData = userDefaults.data(forKey: key) else {
            print("No bookmark data found.")
            return nil
        }

        var isStale = false
        do {
            let docURL = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                // If the bookmark data is stale, create a new bookmark data from the URL
                let newBookmarkData = try docURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                userDefaults.set(newBookmarkData, forKey: key)
            }

            // Start accessing the resource using the security-scoped URL
            let accessGranted = docURL.startAccessingSecurityScopedResource()
            if !accessGranted {
                print("Failed to access the resource.")
                return nil
            }
            return docURL
        } catch {
            print("Error resolving bookmark or creating new bookmark: \(error)")
            return nil
        }
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
