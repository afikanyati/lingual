//
//  Collection+distance.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/28/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

extension Collection {
    func distance(to index: Index) -> Int { distance(from: startIndex, to: index) }
}
