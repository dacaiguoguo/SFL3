//
//  ContentView.swift
//  SFL3
//
//  Created by yanguo sun on 2024/5/28.
//

import SwiftUI
import CoreData

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
    
    @StateObject private var viewModel: FilePathsViewModel
    @StateObject private var iconFinder = IconFinder()
    
    init() {
        _viewModel = StateObject(wrappedValue: FilePathsViewModel())
    }
    
    
    private func fileDidChange() {
        // 重新读取文件
        print("File changed!")
        // 在这里添加你的文件读取逻辑
    }
    var body: some View {
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
                .contentShape(Rectangle()) // Make the entire HStack tappable
                .onTapGesture {
                    openInNS(filePath.path)
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
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now()+1) { [self] in
                    loadFilePaths()
                    iconFinder.findAppIcon(in: "")
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
        if let userUrl = resolvedBookmark(key: "ApplicationRecentDocuments") {
            
            if let paths = readSflWithFile(filePath: userUrl.appendingPathComponent("com.apple.dt.xcode.sfl3").path) {
                for path in paths {
                    addFilePath(path)
                }
            }
        }
        let _ = resolvedBookmark(key: "dev")
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
            } else {
                // 如果存在相同的路径，更新 updatedAt 字段
                let existingFilePath = existingPaths.first!
                existingFilePath.updatedAt = Date()
            }

            // 保存更改，只调用一次 save
            if viewContext.hasChanges {
                try viewContext.save()
            }
        } catch {
            print("Failed to fetch file paths or save file path: \(error)")
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
            print("Error deleting all file paths: \(error)")
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
                    print("Failed to access the resource.")
                }
                print("At bookmark \(accessGranted).")
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
                    print("Failed to access the resource.")
                }
                print("At bookmark \(accessGranted).")
            }
        }
        
    }
    
    
      
      func moveToTop(_ filePath: FilePath) {

          viewContext.perform {
              filePath.isPinned = true // Mark as pinned
              do {
                  try viewContext.save()
              } catch {
                  print("Failed to move to top: \(error)")
              }
          }
      }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
