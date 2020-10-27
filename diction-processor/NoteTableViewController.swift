//
//  Controller.swift
//  diction-processor
//
//  Created by Afika Nyati on 10/24/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import UIKit

let AVATAR_URL = "https://firebasestorage.googleapis.com/v0/b/afika-nyati-website.appspot.com/o/resume%2Fafika.jpg?alt=media&token=f1d32c1d-07b4-48b0-abf9-2200290645c5"

public let noteTableView = NoteTableViewController.shared
public final class NoteTableViewController: UITableViewController {
    static let shared = NoteTableViewController()
    
    // MARK: - General Properties
    var notes = [Note]()
    var detailView: DetailViewController!
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if let indexPath = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: indexPath, animated: true)
        }

        if let notes = viewController.fetchNotes() {
            self.notes = notes
        }
        
        self.detailView = storyboard?.instantiateViewController(withIdentifier: "DetailViewController") as? DetailViewController
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Entry")
        
        self.navigationItem.rightBarButtonItems = [self.getNewNoteButton()]
        viewController.activateListeningIndicator(withStopListeningButton: true)
    }
    
    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.notes.count
    }
    
    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Entry", for: indexPath)
        cell.accessoryType = .disclosureIndicator
        cell.textLabel?.attributedText = self.makeEntryAttributedString(entry: self.notes[indexPath.row], index: indexPath.row)
        cell.textLabel?.numberOfLines = 0
        return cell
    }
    
    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // Set note data
        detailView.setNote(note: self.notes[indexPath.row])
        // Push to detail view
        navigationController?.pushViewController(detailView, animated: true)
    }
    
    func makeEntryAttributedString(entry: Note, index: Int) -> NSAttributedString {
        let titleAttributes = [
            NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .headline),
            NSAttributedString.Key.foregroundColor: UIColor(hex: Utils.LINGUAL_PURPLE) ?? UIColor.purple
        ]
        let subtitleAttributes = [
            NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .subheadline)
        ]

        let titleString = NSMutableAttributedString(string: "Note #\(index + 1)", attributes: titleAttributes)

        let preview = entry.getText().substring(toIndex: Utils.ENTRY_ITEM_PREVIEW_CHAR_COUNT)
        if preview.count > 0 {
            let subtitleString = NSAttributedString(string: "\n\(preview)", attributes: subtitleAttributes)
            titleString.append(subtitleString)
        }

        return titleString
    }
    
    @objc func createNote() {
        // create new note
        let uid = UUID().uuidString
        let note = Note(
            uid: uid,
            filename: "note-\(uid)",
            speaker: Speaker(name: UIDevice.current.name, avatarURL: URL(string: AVATAR_URL)!),
            onListenUpdate: detailView.onNoteListenUpdate,
            onListenStop: detailView.onNoteListenStop,
            onComplete: detailView.onNoteComplete,
            scheduleTempOnEchoFinishHandler: { handler in
                viewController.setEchoHandler(handler: handler)
            }
        )
        
        // Add new note
        self.notes.append(note)
        
        // reload table
        self.tableView.reloadData()
        
        // Save notes
        viewController.saveNotes(notes: self.notes)
    }
    
    func deactivateListeningIndicator() {
        self.navigationItem.leftBarButtonItem = nil
    }
    
    func getNewNoteButton() -> UIBarButtonItem {
        let button  = UIButton(type: .custom)

        button.frame = CGRect(x: 0.0, y: 0.0, width: 40.0, height: 40.0)
        button.addTarget(self, action: #selector(self.createNote), for: .touchUpInside)
        button.setImage(UIImage(systemName: "plus"), for: .normal)
        button.tintColor = UIColor.systemGray
        
        let barButton = UIBarButtonItem(customView: button)
        
        return barButton
    }
}

