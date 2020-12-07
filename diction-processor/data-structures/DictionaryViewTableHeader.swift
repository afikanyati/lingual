//
//  DictionaryViewTableHeader.swift
//  diction-processor
//
//  Created by Afika Nyati on 12/6/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import UIKit

// Reference: https://developer.apple.com/documentation/uikit/views_and_controls/table_views/adding_headers_and_footers_to_table_sections
class DictionaryViewTableHeader: UITableViewHeaderFooterView {
    let title = UILabel()
    let details = UILabel()
    let button = UIButton()
//    let chevron =

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        configureContents()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configureContents() {
//        let button = UIButton(type: .custom)
//        button.frame = CGRect(
//            x: 0.0,
//            y: 0.0,
//            width: Utils.NAVBAR_BUTTON_LENGTH,
//            height: Utils.NAVBAR_BUTTON_LENGTH
//        )
//        button.tintColor = UIColor.systemGray
//        button.addTarget(self, action: #selector(self.toggleAccordion), for: .touchDown)
//
//        if self.sections[section].isAccordion && self.sections[section].isExpanded {
//            button.setImage(UIImage(systemName: "chevron.up"), for: .normal)
//        } else if self.sections[section].isAccordion && !self.sections[section].isExpanded {
//            button.setImage(UIImage(systemName: "chevron.down"), for: .normal)
//        }
        
        button.translatesAutoresizingMaskIntoConstraints = false
        details.translatesAutoresizingMaskIntoConstraints = false
        title.translatesAutoresizingMaskIntoConstraints = false
        
        // Title
        title.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        title.textColor = UIColor.black
        title.numberOfLines = 0
        
        // Details
        details.font = UIFont.systemFont(ofSize: 14)
        details.textColor = UIColor.gray
        details.numberOfLines = 0

        contentView.addSubview(button)
        contentView.addSubview(details)
        contentView.addSubview(title)

        // Center the image vertically and place it near the leading
        // edge of the view. Constrain its width and height to 50 points.
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            button.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            button.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        
            // Center the label vertically, and use it to fill the remaining
            // space in the header view.
            title.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            title.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            title.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor, constant: 10),
            
            details.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            details.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            details.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor, constant: 40),
            details.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor, constant: -10),
        ])
    }
}
