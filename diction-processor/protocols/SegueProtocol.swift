//
//  SegueProtocol.swift
//  diction-processor
//
//  Created by Afika Nyati on 10/30/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import UIKit

protocol SegueProtocol {
    func segueIdentifierCase(for segue: UIStoryboardSegue) -> Segues?
}

enum Segues: String {
    case moveFromEntryTableToDetail
    case moveFromEntryTableToDictionary
    case moveFromDetailToEntryTable
    case moveFromDictionaryToEntryTable
    case noIdentifier = ""
}

extension SegueProtocol where Self: UIViewController {
    func segueIdentifierCase(for segue: UIStoryboardSegue) -> Segues? {
        guard let identifier = segue.identifier,
            let identifierCase = Segues(rawValue: identifier) else {
            return Segues(rawValue: "")
        }
        return identifierCase
    }
}
