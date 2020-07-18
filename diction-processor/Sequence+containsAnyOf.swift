//
//  Sequence+containsAnyOf.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/17/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

public extension Sequence where Element: Equatable {
    func contains(anyOf sequence: [Element]) -> Bool {
        return self.filter { sequence.contains($0) }.count > 0
    }
}
