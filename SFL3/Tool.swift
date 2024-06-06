//
//  Tool.swift
//  SFL3
//
//  Created by yanguo sun on 2024/5/30.
//

import Foundation
import SwiftUI


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

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()



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
        if let recentListInfo = unarchiver.decodeObject(of: [NSObject.self, NSDictionary.self, NSArray.self], forKey: NSKeyedArchiveRootObjectKey) as? [String: Any] {
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


func openInFinder(_ path: String?) {
    guard let path = path, let url = URL(string: path) else { return }
    NSWorkspace.shared.activateFileViewerSelecting([url])
}


func openInNS(_ path: String?) {
    guard let path = path else {
        print("Invalid path")
        return
    }
    let url = URL(fileURLWithPath: path)
    let packageUrl = url.appending(path: "Package.swift")
    let packageSuccess = NSWorkspace.shared.open(packageUrl)
    if packageSuccess {
        print("Open package result: \(packageSuccess)")
    } else {
        let success = NSWorkspace.shared.open(url)
        print("Open result: \(success)")
    }
    // Attempt to open the URL in Finder
    
    // Log the result of the attempt
}


func uninstallApp() {
        let task = Process()
        task.launchPath = "/usr/bin/xcrun"
        task.arguments = ["simctl", "uninstall", "iPhone 15 Pro", "authenticator.2fa.app"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        task.launch()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            print(output)
        }
    }
