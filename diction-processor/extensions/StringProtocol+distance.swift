//
//  StringProtocol+distance.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/28/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

extension StringProtocol {
    func distance(of element: Element) -> Int? { firstIndex(of: element)?.distance(in: self) }
    func distance<S: StringProtocol>(of string: S) -> Int? { range(of: string)?.lowerBound.distance(in: self) }
}
