//
//  StringIndex+distance.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/28/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

extension String.Index {
    func distance<S: StringProtocol>(in string: S) -> Int { string.distance(to: self) }
}
