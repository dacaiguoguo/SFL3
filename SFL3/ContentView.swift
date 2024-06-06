//
//  ContentView.swift
//  SFL3
//
//  Created by yanguo sun on 2024/5/28.
//

import SwiftUI
import CoreData
import os.log

enum Log {
    static let subsystem = Bundle.main.bundleIdentifier!
    
    static let general = OSLog(subsystem: subsystem, category: "general")
    static let network = OSLog(subsystem: subsystem, category: "network")
    static let database = OSLog(subsystem: subsystem, category: "database")
}

func logDebug(_ message: StaticString, _ args: CVarArg..., category: OSLog = Log.general) {
#if DEBUG
    os_log(message, log: category, type: .debug, args)
#endif
}

func logInfo(_ message: StaticString, _ args: CVarArg..., category: OSLog = Log.general) {
    os_log(message, log: category, type: .info, args)
}

func logError(_ message: StaticString, _ args: CVarArg..., category: OSLog = Log.general) {
    os_log(message, log: category, type: .error, args)
}


struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        entity: FilePath.entity(),
        sortDescriptors: [
            NSSortDescriptor(keyPath: \FilePath.isPinned, ascending: false), // Pinned items first
            NSSortDescriptor(keyPath: \FilePath.updatedAt, ascending: false)   // Then by creation time
        ],
        animation: .default)
    private var filePaths: FetchedResults<FilePath>
    @State private var counter = 0
    
    private func refreshUI() {
        self.filePaths.nsPredicate = NSPredicate(value: true)  // 触发重新查询和UI更新
        counter += 1
    }
    
    @StateObject private var viewModel: FilePathsViewModel
    @StateObject private var iconFinder = IconFinder()
    
    init() {
        _viewModel = StateObject(wrappedValue: FilePathsViewModel())
    }
    
    var body: some View {
        List {
            ForEach(filePaths) { filePath in
                HStack {
                    if let iconData = filePath.icon, let nsImage = NSImage(data: iconData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "pencil.line")
                            .resizable()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
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
                        Image(systemName: filePath.isPinned ? "pin.fill" : "pin")
                    }
                    Button(action: uninstallApp) {
                        Label("Uninstall App", systemImage: "trash")
                    }
                }
                .contentShape(Rectangle()) // Make the entire HStack tappable
                .onTapGesture {
                    openInNS(filePath.path)
                }
            }
        }
        .id(counter) // 强制重新创建视图
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now()+1) { [self] in
                loadFilePaths()
                print("NSHomeDirectory():\(NSHomeDirectory())")
                // ~/Library/Containers/com.dacaiguoguo.SFL3/Data/Library/Application Support/SFL3/SFL3.sqlite
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .filePathsDidUpdate)) { _ in
            loadFilePaths()
        }
    }
    
    private func openInFinder(_ path: String?) {
        guard let path = path else { return }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    private func loadFilePaths() {
        let _ = resolvedBookmark(key: "dev")
        if let userUrl = resolvedBookmark(key: "ApplicationRecentDocuments") {
            
            if let paths = readSflWithFile(filePath: userUrl.appendingPathComponent("com.apple.dt.xcode.sfl3").path) {
                for path in paths {
                    addFilePath(path)
                }
            }
        }
    }
    
    private func addFilePath(_ path: String) {
        // 检查是否已经存在相同的路径
        let fetchRequest: NSFetchRequest<FilePath> = FilePath.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "path == %@", path)
        
        do {
            let existingPaths = try viewContext.fetch(fetchRequest)
            var filePathObject: FilePath
            
            if existingPaths.isEmpty {
                // 如果没有相同的路径，插入新的路径
                filePathObject = FilePath(context: viewContext)
                filePathObject.path = path
                filePathObject.createdAt = Date()
                filePathObject.updatedAt = Date()
                filePathObject.isPinned = false
            } else {
                // 如果存在相同的路径，更新 updatedAt 字段
                filePathObject = existingPaths.first!
                filePathObject.updatedAt = Date()
            }
            
            // 调用 findAppIcon 方法
            findAppIcon(in: path) { iconData in
                filePathObject.icon = iconData
                
                // 保存更改，只调用一次 save
                if viewContext.hasChanges {
                    do {
                        try viewContext.save()
                    } catch {
                        print("Failed to save file path with icon: \(error)")
                    }
                }
            }
        } catch {
            print("Failed to fetch file paths: \(error)")
        }
    }
    
    private func findAppIcon(in filePath: String, completion: @escaping (Data?) -> Void) {
        DispatchQueue.global(qos: .default).async {
            let fileManager = FileManager.default
            let workPathURL = URL(fileURLWithPath: filePath).deletingLastPathComponent()
            guard let enumerator = fileManager.enumerator(at: workPathURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            var appiconsetURL: URL?
            var depthCounter = [URL: Int]()
            
            while let fileURL = enumerator.nextObject() as? URL {
                let parentURL = fileURL.deletingLastPathComponent()
                let currentDepth = (depthCounter[parentURL] ?? 0) + 1
                depthCounter[fileURL] = currentDepth
                
                if fileURL.lastPathComponent == "Pods" || fileURL.pathExtension == "app" || fileURL.pathExtension == "Watch" {
                    enumerator.skipDescendants()
                    continue
                }
                
                
                // print("fileURL: \(fileURL), depth: \(currentDepth)")
                // logDebug("fileURL found: %{public}@", fileURL.absoluteString)
                
                if currentDepth > 5 {
                    enumerator.skipDescendants()
                    continue
                }
                
                if fileURL.pathExtension == "appiconset" {
                    appiconsetURL = fileURL
                    break // Stop after finding the first appiconset folder
                }
            }
            
            var foundIcon = false
            
            if let appiconset = appiconsetURL {
                // logDebug("appiconsetURL found: %{public}@", appiconset.absoluteString)
                guard let iconEnumerator = fileManager.enumerator(at: appiconset, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
                
                while let iconFileURL = iconEnumerator.nextObject() as? URL, !foundIcon {
                    if iconFileURL.pathExtension == "png" {
                        // logDebug("iconFileURL found: %{public}@", iconFileURL.absoluteString)
                        if let iconData = try? Data(contentsOf: iconFileURL) {
                            DispatchQueue.main.async {
                                completion(iconData)
                            }
                            foundIcon = true
                        }
                    }
                }
            }
            if !foundIcon {
                logDebug("No appiconsetURL found: %{public}@", workPathURL.absoluteString)
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    
    func deleteAllFilePaths() {
        
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
            logDebug("Error deleting all file paths:  %{public}@", error.localizedDescription)
            
        }
        refreshUI()
    }
    
    func requestAgent() {
        let openPanel = NSOpenPanel()
        openPanel.prompt = "Grant Access"
        openPanel.message = "Please grant access to the folder"
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = false
        // 尝试设置一个默认目录
        let path = NSString(string: "~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments").expandingTildeInPath
        openPanel.directoryURL = URL(fileURLWithPath: path)
        openPanel.begin { [self] (result) -> Void in
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
                    logInfo("Failed to access the resource.")
                }
                logDebug("At bookmark :  %{public}@", accessGranted)
                
            }
        }
    }
    
    func requestDev() {
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
                    logInfo("Failed to access the resource.")
                }
                print("At bookmark \(accessGranted).")
            }
        }
        
    }
    
    
    
    func moveToTop(_ filePath: FilePath) {
        
        viewContext.perform {
            filePath.isPinned = !filePath.isPinned // Mark as pinned
            filePath.updatedAt = Date()
            do {
                try viewContext.save()
            } catch {
                print("Failed to move to top: \(error)")
            }
        }
    }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
