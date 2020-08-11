//
//  Queue.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/22/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

// Modified from: https://www.raywenderlich.com/848-swift-algorithm-club-swift-queue-data-structure

public struct Queue<T> {
    fileprivate var list = LinkedList<T>()

    public var isEmpty: Bool {
        return list.isEmpty
    }

    public mutating func enqueue(_ element: T) {
        list.append(value: element)
    }

    public mutating func dequeue() -> T? {
        guard !list.isEmpty, let element = list.first else { return nil }

        let _ = list.remove(node: element)

        return element.value
    }

    public func peek() -> T? {
        return list.first?.value
    }
}

extension Queue: CustomStringConvertible {
    public var description: String {
        return list.description
    }
}
