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

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: true)],
        animation: .default)
    private var items: FetchedResults<Item>

    @State private var filePaths: [String] = []

    init() {
        let filePath = Bundle.main.path(forResource: "com.apple.dt.xcode", ofType: "sfl3") ?? ""
        self._filePaths = State(initialValue: readSflWithFile(filePath: filePath) ?? [])
    }

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Files")) {
                    ForEach(filePaths, id: \.self) { filePath in
                        Text(filePath)
                    }
                }
                
                Section(header: Text("Core Data Items")) {
                    ForEach(items) { item in
                        NavigationLink(destination: Text("Item at \(item.timestamp!, formatter: itemFormatter)")) {
                            Text(item.timestamp!, formatter: itemFormatter)
                        }
                    }
                    .onDelete(perform: deleteItems)
                }
            }
            .toolbar {
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
            Text("Select an item")
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { items[$0] }.forEach(viewContext.delete)
            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(context: viewContext)
            newItem.timestamp = Date()
            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
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
