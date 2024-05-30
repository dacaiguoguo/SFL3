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
