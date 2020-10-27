//
//  DetailViewController.swift
//  diction-processor
//
//  Created by Afika Nyati on 10/24/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import UIKit
import Speech
import AVFoundation
import NaturalLanguage

public final class DetailViewController: UIViewController {
    // MARK: - Outlets and Views
    
    // ===== Menu Bar =====
    @IBOutlet weak var startNoteButton: UIView?
    @IBOutlet weak var editNoteButton: UIView?
    @IBOutlet weak var resumeNoteButton: UIView?
    @IBOutlet weak var stopListeningNoteButton: UIView?
    @IBOutlet weak var playButton: UIView?
    @IBOutlet weak var stopPlayingButton: UIView?
    @IBOutlet weak var echoButton: UIView?
    @IBOutlet weak var stopEchoButton: UIView?
    @IBOutlet weak var exportButton: UIView?
    @IBOutlet weak var walkButton: UIView?
    
    // ===== Command Bar =====
    
    // Resting Buttons
    @IBOutlet weak var runButton: UIView?
    @IBOutlet weak var pauseButton: UIView?
    
    // Conditional Buttons
    @IBOutlet weak var moveHereButton: UIView?
    @IBOutlet weak var inspectClipboardButton: UIView?
    @IBOutlet weak var playCommitButton: UIView?
    @IBOutlet weak var pauseEchoButton: UIView?
    @IBOutlet weak var skipBackwardButton: UIView?
    @IBOutlet weak var skipForwardButton: UIView?
    @IBOutlet weak var playbackRateButton: UIView?
    @IBOutlet weak var echoRateButton: UIView?
    
    // Selection Buttons
    @IBOutlet weak var increaseRateButton: UIView?
    @IBOutlet weak var decreaseRateButton: UIView?
    @IBOutlet weak var deleteSelectionButton: UIView?
    @IBOutlet weak var updateSelectionButton: UIView?
    @IBOutlet weak var cancelUpdateSelectionButton: UIView?
    @IBOutlet weak var copySelectionButton: UIView?
    @IBOutlet weak var cutSelectionButton: UIView?
    
    // Text View
    @IBOutlet weak var textView: UITextView?
    @IBOutlet weak var textViewPositionTop: NSLayoutConstraint?
    @IBOutlet weak var textViewPositionBottom: NSLayoutConstraint?
    
    // Indicators
    @IBOutlet weak var soundIntensityIndicator: UIView?
    @IBOutlet weak var soundIntensityIndicatorHeight: NSLayoutConstraint?
    @IBOutlet weak var soundIntensityIndicatorPositionBottom: NSLayoutConstraint?
    @IBOutlet weak var pitchLabel: UILabel?
    @IBOutlet weak var transformationLabel: UILabel?
    
    // Scroll View
    @IBOutlet weak var scrollView: UIScrollView?
    @IBOutlet weak var scrollViewPositionTop: NSLayoutConstraint?

    // Command Bar
    @IBOutlet weak var commandBar: UIStackView?
    @IBOutlet weak var commandBarPositionTop: NSLayoutConstraint?
    
    // Menu Bar
    @IBOutlet weak var menuBar: UIStackView?
    @IBOutlet weak var menuBarPositionBottom: NSLayoutConstraint?
    
    // Slider
    @IBOutlet weak var sliderView: UIView?
    @IBOutlet weak var sliderViewPositionTop: NSLayoutConstraint?
    @IBOutlet weak var slider: UISlider?
    @IBOutlet weak var exitSliderButton: UIView?
    
    // Walk
    @IBOutlet weak var walkNextElementButton: UIView?
    @IBOutlet weak var walkPreviousElementButton: UIView?
    @IBOutlet weak var exitWalkRunButton: UIView?
    
    // Run
    @IBOutlet weak var haltRunButton: UIView?

    // Cursor
    var cursorView: UIView?
    
    // MARK: - General Properties
    let font = UIFont.systemFont(ofSize: 18.0)
    var sliderIsVisible = false
    var sliderType: SliderType?
    var cursorBlinkTimer: Timer?
    var onNoteListenUpdate: ((_ text: String, _ bufferRange: NSRange?, _ highlightRange: NSRange?) -> Void)?
    var onNoteListenStop: (() -> Void)?
    var onNoteComplete: (() -> Void)?
    var UITimer: Timer?
    /// Stores a UI handler to be executed when new sound intensity data is received
    private(set) var soundIntensityHandler: ((_ power: Double?) -> Void)?
    /// Stores a UI handler to be executed when new pitch data is received
    private(set) var pitchHandler: ((_ pitchDatum: PitchDatum?) -> Void)?
    
    // MARK: - General Audio Properties
    @objc dynamic var session = AVAudioSession.sharedInstance()
    var note: Note?
    var tempNote: Note?

    // MARK: - Speech Recognition Properties
    var audioEngine = AVAudioEngine()
    let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    var request: SFSpeechAudioBufferRecognitionRequest?
    var recognitionTask: SFSpeechRecognitionTask?
    
    // MARK: - Cached Properties
    var cachedTextViewSelectedRange: NSRange?
    
    // MARK: - Lifecycle Methods
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up note handlers
        self.configureNoteHandlers()
        
        // Set up ui handlers
        self.configureUIHandlers()
        
        // Prepare UI
        self.prepareMenuBar()
        self.prepareCommandBar()
        self.prepareSlider()
        self.prepareTextView()
        self.adjustCommandBar()
        self.adjustMenuBar()
        self.transformationLabel?.isHidden = true
        
        // add observer to hasSelection
        selectionCursor.addObserver(
            self,
            forKeyPath: "hasSelection",
            options: [.old, .new],
            context: nil
        )
        
        // add observer to isUpdatingSelection
        selectionCursor.addObserver(
            self,
            forKeyPath: "isUpdatingSelection",
            options: [.old, .new],
            context: nil
        )
        
        // add observer to isPromptingForUpdateAcceptance
        selectionCursor.addObserver(
            self,
            forKeyPath: "isPromptingForUpdateAcceptance",
            options: [.old, .new],
            context: nil
        )
        
        // add observer to clipboard
        selectionCursor.addObserver(
            self,
            forKeyPath: "clipboard",
            options: [.old, .new],
            context: nil
        )
        
        self.textView?.addObserver(
            self,
            forKeyPath: "selectedTextRange",
            options: [.old, .new],
            context: nil
        )
        
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(self.handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        self.textView?.addGestureRecognizer(singleTap)
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // remove observer from hasSelection
        selectionCursor.removeObserver(
            self,
            forKeyPath: "hasSelection",
            context: nil
        )
        
        // remove observer from isUpdatingSelection
        selectionCursor.removeObserver(
            self,
            forKeyPath: "isUpdatingSelection",
            context: nil
        )
        
        // remove observer from isPromptingForUpdateAcceptance
        selectionCursor.removeObserver(
            self,
            forKeyPath: "isPromptingForUpdateAcceptance",
            context: nil
        )
        
        // remove observer from clipboard
        selectionCursor.removeObserver(
            self,
            forKeyPath: "clipboard",
            context: nil
        )
        
        self.textView?.removeObserver(
            self,
            forKeyPath: "selectedTextRange",
            context: nil
        )
    }
    
    // MARK: - Configuration Methods
    
    func configureNoteHandlers() {
        self.onNoteListenUpdate = {[weak self] text, highlightRange, bufferRange in
            DispatchQueue.main.async {
                self?.updateUIText(text: text, highlightRange: highlightRange, bufferRange: bufferRange, transformations: self!.note!.transformations)
                self?.adjustCommandBar()
                self?.adjustMenuBar()
            }
        }
        
        self.onNoteListenStop = {[weak self] in
            DispatchQueue.main.async {
                self?.updateUIText(text: self!.note!.getText(), transformations: self!.note!.transformations)
                self?.stopRecordingUITimer()
                self?.adjustCommandBar()
                self?.adjustMenuBar()
                self?.soundIntensityIndicatorHeight?.constant = 0
            }
        }
        
        self.onNoteComplete = {[weak self] in
            // Play sound
            Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
                soundEngine.saveNote()
            }

            DispatchQueue.main.async {
                self?.stopRecordingUITimer()
                self?.soundIntensityIndicatorHeight?.constant = 0
                self?.adjustCommandBar()
                self?.adjustMenuBar()
                self?.navigationItem.rightBarButtonItems = [self!.getDeleteNoteButton()]
                if let _ = selectionCursor.clipboard {
                    self?.navigationItem.rightBarButtonItems?.insert(self!.getPasteClipboardButton(), at: 0)
                }
                viewController.activateListeningIndicator(withStopListeningButton: true)
            }
        }
    }
    
    func configureUIHandlers() {
        self.soundIntensityHandler = { power in
            if let power = power {
                DispatchQueue.main.async {
                    var screenHeight = self.view.safeAreaLayoutGuide.layoutFrame.height
                    if let _ = self.note {
                        screenHeight -= Utils.COMMAND_BAR_HEIGHT
                    }
                    if let _ = self.note {
                        screenHeight -= Utils.MENU_BAR_HEIGHT
                    }
                    let height = CGFloat(Utils.normalizedPower(power: power, minPower: viewController.minPower)) * screenHeight
                    let soundIntensityHeight: CGFloat = CGFloat(min(height, screenHeight))
                    self.soundIntensityIndicatorHeight?.constant = soundIntensityHeight
                }
            }
        }
        self.pitchHandler = { pitchDatum in
            if let pitchDatum = pitchDatum, let note = self.note, !note.isPlayingNote {
                DispatchQueue.main.async {
                    let pitch = pitchDatum.pitch?.note.string
                    self.pitchLabel?.text = pitch
                }
            }
        }
    }
    
    func prepareGeneralView() {
        self.soundIntensityIndicator?.backgroundColor = UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red
        self.pitchLabel?.textColor = UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red
        self.transformationLabel?.textColor = UIColor(hex: Utils.LINGUAL_ORANGE) ?? UIColor.orange
    }
    
    func prepareMenuBar() {
        guard let menuBar = self.menuBar else { return }
        menuBar.layer.shadowPath =
              UIBezierPath(
                roundedRect: menuBar.bounds,
                cornerRadius: menuBar.layer.cornerRadius
              ).cgPath
        menuBar.layer.shadowColor = UIColor.black.cgColor
        menuBar.layer.shadowOpacity = 0.5
        menuBar.layer.shadowOffset = CGSize(width: 0, height: -5)
        menuBar.layer.shadowRadius = 5
        menuBar.layer.masksToBounds = false
    }
    
    func prepareCommandBar() {
        guard let commandBar = self.commandBar else { return }
        commandBar.backgroundColor = UIColor(hex: Utils.LINGUAL_PURPLE) ?? UIColor.purple
        commandBar.layer.shadowPath =
              UIBezierPath(
                roundedRect: commandBar.bounds,
                cornerRadius: commandBar.layer.cornerRadius
              ).cgPath
        commandBar.layer.shadowColor = UIColor.black.cgColor
        commandBar.layer.shadowOpacity = 0.5
        commandBar.layer.shadowOffset = CGSize(width: 0, height: 5)
        commandBar.layer.shadowRadius = 5
        commandBar.layer.masksToBounds = false
    }
    
    func prepareSlider() {
        self.slider?.minimumValue = Utils.MINIMUM_PLAYBACK_RATE
        self.slider?.maximumValue = Utils.MAXIMUM_PLAYBACK_RATE
        self.slider?.isContinuous = true
        self.slider?.addTarget(self, action: #selector(self.sliderValueDidChange), for: .valueChanged)
        
        // Hide Slider
        self.setSliderVisibility(as: false)
    }
    
    // Reference: https://stackoverflow.com/questions/3231896/how-to-set-margins-padding-in-uitextview
    func prepareTextView() {
        // Set textContainer font size
        self.textView?.font = self.font
        self.textView?.textContainerInset = UIEdgeInsets(
            top: Utils.TEXT_VIEW_PADDING_TOP,
            left: Utils.TEXT_VIEW_PADDING_LEFT,
            bottom: Utils.TEXT_VIEW_PADDING_BOTTOM,
            right: Utils.TEXT_VIEW_PADDING_RIGHT
        )
    }
    
    func getDeleteNoteButton() -> UIBarButtonItem {
        let button  = UIButton(type: .custom)

        button.frame = CGRect(x: 0.0, y: 0.0, width: 40.0, height: 40.0)
        button.addTarget(self, action: #selector(self.deleteNote), for: .touchUpInside)
        button.setImage(UIImage(systemName: "trash"), for: .normal)
        button.tintColor = UIColor.systemGray
        
        let barButton = UIBarButtonItem(customView: button)
        
        return barButton
    }
    
    func getPasteClipboardButton() -> UIBarButtonItem {
        let button  = UIButton(type: .custom)

        button.frame = CGRect(x: 0.0, y: 0.0, width: 40.0, height: 40.0)
        button.addTarget(self, action: #selector(self.pasteClipboard), for: .touchUpInside)
        button.setImage(UIImage(systemName: "doc.on.clipboard"), for: .normal)
        button.tintColor = UIColor.systemGray
        
        let barButton = UIBarButtonItem(customView: button)

        return barButton
    }
    
    // MARK: - UI Methods

    func setCursorVisibility(as visible: Bool) {
        print("=====  Set Cursor Visibility: \(visible) =====")
        // manage cursor view
        if self.cursorView == nil && visible && self.textView?.attributedText.length == 0 {
            // initial set up for cursor
            self.cursorView = UIView()
            Utils.initializeCursor(
                textView: self.textView!,
                cursorView: self.cursorView!,
                font: self.font
            )
            
            // Set UIView background color
            self.cursorView!.backgroundColor = UIColor.systemBlue
            
            // Create corner radius
            self.cursorView!.layer.cornerRadius = CGFloat(Utils.CURSOR_WIDTH / 2)
            
            // Add above UIView object as the main view's subview.
            self.view.addSubview(self.cursorView!)
        } else if let _ = self.cursorView, visible && self.textView!.attributedText.length > 0 && self.cursorView!.alpha == 0 {
            // show cursor again
            self.cursorView!.alpha = 1
        } else if let _ = self.cursorView, let note = self.note, !visible && note.isListeningForSpeech {
            // hide cursor
            self.cursorView!.alpha = 0
        }
        
        // manage cursor model
        if visible {
            selectionCursor.setTextView(textView: self.textView)
            selectionCursor.setCursorView(cursorView: cursorView)
            selectionCursor.setNote(note: self.note)
            selectionCursor.setFont(font: self.font)
            
            if self.cursorBlinkTimer != nil {
                // Stopped cursor blinking that's already running
                // To avoid two instances of blinking timers
                self.cursorBlinkTimer?.invalidate()
            }
            
            // start cursor blink
            self.cursorBlinkTimer = Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_CURSOR_BLINK_RATE, repeats: true) { [weak self] timer in
                if let cursorView = self?.cursorView, cursorView.alpha == 1 {
                    UIView.animate(withDuration: Utils.DEFAULT_CURSOR_BLINK_TRANSITION_DURATION) {
                        self!.cursorView!.alpha = 0
                    }
                } else if let cursorView = self?.cursorView, cursorView.alpha == 0 {
                    UIView.animate(withDuration: Utils.DEFAULT_CURSOR_BLINK_TRANSITION_DURATION) {
                        self!.cursorView!.alpha = 1
                    }
                }
            }
        } else {
            // stop cursor blink
            if self.cursorBlinkTimer != nil {
                self.cursorBlinkTimer?.invalidate()
                self.cursorBlinkTimer = nil
            }
        }
    }
    
    func removeCursor() {
        print("===== Remove Cursor =====")
        // selectionCursor.reset()

        // remove cursor
        if let cursorView = self.cursorView {
            cursorView.removeFromSuperview()
            self.cursorView = nil
        }
    }
    
    func setMenuBarVisibility(as visible: Bool) {
        if visible {
            // Show Command Bar
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.menuBar?.alpha = 1
                    self.menuBarPositionBottom?.constant = 0
                }
            )
            // Reduce TextView Height
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.textViewPositionBottom?.constant = Utils.MENU_BAR_HEIGHT
                }
            )
            
            // Move Sound Intensity Indicator Bottom
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.soundIntensityIndicatorPositionBottom?.constant = Utils.MENU_BAR_HEIGHT
                }
            )
        } else {
            // Hide Command Bar
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.menuBar?.alpha = 0
                    self.menuBarPositionBottom?.constant = -20
                }
            )
            
            // Incrase TextView Height
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.textViewPositionBottom?.constant = 0
                }
            )
            
            // Move Sound Intensity Indicator Bottom
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.soundIntensityIndicatorPositionBottom?.constant = 0
                }
            )
        }
    }
    
    func setScrollViewVisibility(as visible: Bool) {
        if visible {
            // Show Command Bar
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.scrollView?.alpha = 1
                    self.scrollViewPositionTop?.constant = 0
                }
            )
            // Reduce TextView Height
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.textViewPositionTop?.constant = Utils.SCROLL_VIEW_HEIGHT
                }
            )
            
            // Adjust cursor
            Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_VIEW_TRANSITION_DURATION, repeats: false) { [weak self] timer in
                // Adjust cursor to appropriate position
                if selectionCursor.isVisible && !selectionCursor.hasSelection {
                    selectionCursor.textViewDidChange(self!.textView!)
                }
            }
        } else {
            // Hide Command Bar
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.scrollView?.alpha = 0
                    self.scrollViewPositionTop?.constant = -20
                }
            )
            
            // Expand TextView Height
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.textViewPositionTop?.constant = 0
                }
            )

            // Adjust cursor
            Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_VIEW_TRANSITION_DURATION, repeats: false) { [weak self] timer in
                // Adjust cursor to appropriate position
                if selectionCursor.isVisible && !selectionCursor.hasSelection {
                    selectionCursor.textViewDidChange(self!.textView!)
                }
            }
        }
    }
    
    func setCommandBarVisibility(as visible: Bool) {
        if visible {
            // Show Slider View
            self.commandBar?.isHidden = false

            // Animate in Command Bar
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.commandBar?.alpha = 1
                }
            )
        } else {
            // Animate out Command Bar
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.commandBar?.alpha = 0
                }
            )
            
            // Hide Command Bar
            Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_VIEW_TRANSITION_DURATION, repeats: false) { [weak self] timer in
                self!.commandBar?.isHidden = true
            }
        }
    }
    
    func setSliderVisibility(as visible: Bool) {
        if visible {
            // Show Slider View
            self.sliderView?.isHidden = false

            // Animate in Slider View
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.sliderView?.alpha = 1
                }
            )
        } else {
            // Animate out Slider View
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.sliderView?.alpha = 0
                }
            )
            
            // Hide Slider View
            Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_VIEW_TRANSITION_DURATION, repeats: false) { [weak self] timer in
                self!.sliderView?.isHidden = true
            }
        }
    }
    
    func updateUIText(text: String, highlightRange: NSRange? = nil, bufferRange: NSRange? = nil, transformations: [NoteTransformation]? = nil) {
        // Cache selection
        if let selectionTextRange = selectionCursor.selectionTextRange, selectionCursor.hasSelection {
            self.cachedTextViewSelectedRange = selectionTextRange
        }

        let mutableAttributedString = NSMutableAttributedString(string: text)

        if let bufferRange = bufferRange, bufferRange.length > 0 && text.count > 0 {
            // If passage is in buffer, we make gray text
            mutableAttributedString.addAttribute(.foregroundColor, value: UIColor.systemGray, range: bufferRange)
        } else if let highlightRange = highlightRange, highlightRange.length > 0 && text.count > 0 {
            // If words in note are being echoed, we highlight them
            mutableAttributedString.addAttribute(.foregroundColor, value: UIColor.white, range: highlightRange)
            mutableAttributedString.addAttribute(.backgroundColor, value: UIColor(hex: Utils.LINGUAL_PURPLE) ?? UIColor.purple, range: highlightRange)
        }
        
        // Emphasize all transformations text
        if let transformations = transformations {
            for transformation in transformations {
                mutableAttributedString.addAttribute(.foregroundColor, value: UIColor(hex: Utils.LINGUAL_ORANGE) ?? UIColor.orange, range: transformation.textRange)
            }
        }
        
        // Add all accumulated attributes to text object
        self.textView?.attributedText = mutableAttributedString
        // Set font
        self.textView?.font = self.font
        
        if let cachedTextViewSelectedRange = self.cachedTextViewSelectedRange {
            print("\t[updateUIText] Adding back cached selection text...")
            selectionCursor.manualSelection(range: cachedTextViewSelectedRange)
            self.cachedTextViewSelectedRange = nil
        }
        
        // Notify of text change
        if selectionCursor.isVisible {
            selectionCursor.textViewDidChange(self.textView!)
        }
    }
    
    /**
        Presents timer to view.

        - Parameter recording: Whether the timer should be set to be a recording.
    */
    func startRecordingUITimer(recording: Bool) {
        if self.UITimer != nil {
            self.stopRecordingUITimer()
        }
        
        if recording {
            DispatchQueue.main.async {
                self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red]
            }
        }
        
        if selectionCursor.hasSelection && selectionCursor.direction == .forwards {
            // we have selection in forwards direction
            // visually present the time range of selection
            self.navigationItem.title = "\(Utils.formattedTime(time: self.note!.getDurationListening()))\(" [\(Utils.formattedTime(time: Float(selectionCursor.anchor!.timeMapping.target.start.seconds))) - \(Utils.formattedTime(time: Float(selectionCursor.focus!.timeMapping.target.end.seconds)))]")"
        } else if selectionCursor.hasSelection && selectionCursor.direction == .backwards {
            // we have selection in backwards direction
            // visually present the time range of selection
            self.navigationItem.title = "\(Utils.formattedTime(time: self.note!.getDurationListening()))\(" [\(Utils.formattedTime(time: Float(selectionCursor.focus!.timeMapping.target.start.seconds))) - \(Utils.formattedTime(time: Float(selectionCursor.anchor!.timeMapping.target.end.seconds)))]")"
        } else {
            // we don't have a selection
            // we might have a cursor placed mid-sentence however
            // present time of cursor
            self.navigationItem.title = "\(Utils.formattedTime(time: self.note!.getDurationListening()))\(selectionCursor.cachedAnchor != nil ? " [\(Utils.formattedTime(time: Float(selectionCursor.cachedAnchor!.timeMapping.target.end.seconds)))]" : "")"
        }
        
        self.UITimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {[weak self] timer in
            // Terminate timer if no longer recording
            if !self!.note!.isListeningForSpeech {
                self!.UITimer?.invalidate()
                self!.UITimer = nil
            }

            if selectionCursor.hasSelection && selectionCursor.direction == .forwards {
                // we have selection in forwards direction
                // visually present the time range of selection
                self?.navigationItem.title = "\(Utils.formattedTime(time: self!.note!.getDurationListening()))\(" [\(Utils.formattedTime(time: Float(selectionCursor.anchor!.timeMapping.target.start.seconds))) - \(Utils.formattedTime(time: Float(selectionCursor.focus!.timeMapping.target.end.seconds)))]")"
            } else if selectionCursor.hasSelection && selectionCursor.direction == .backwards {
                // we have selection in backwards direction
                // visually present the time range of selection
                self?.navigationItem.title = "\(Utils.formattedTime(time: self!.note!.getDurationListening()))\(" [\(Utils.formattedTime(time: Float(selectionCursor.focus!.timeMapping.target.start.seconds))) - \(Utils.formattedTime(time: Float(selectionCursor.anchor!.timeMapping.target.end.seconds)))]")"
            } else if self!.note!.isListeningForSpeech {
                // we don't have a selection
                // we might have a cursor placed mid-sentence however
                // present time of cursor
                self?.navigationItem.title = "\(Utils.formattedTime(time: self!.note!.getDurationListening()))\(selectionCursor.cachedAnchor != nil ? " [\(Utils.formattedTime(time: Float(selectionCursor.cachedAnchor!.timeMapping.target.end.seconds)))]" : "")"
            }
        }
    }
    
    /**
        Removes timer from view.
    */
    func stopRecordingUITimer() {
        self.UITimer?.invalidate()
        self.UITimer = nil
        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.black]
        self.navigationItem.title = ""
        print("SWAGG")
    }
    
    func adjustMenuBar() {
        print("===== Adjust Menu Bar =====")

        // Start Note Button
        if let note = self.note,
           !note.isListeningForSpeech &&
            note.noteSegments.count == 0 &&
            viewController.listeningPermissionsGranted {
            self.showButton(self.startNoteButton)
        } else {
            self.hideButton(self.startNoteButton)
        }
        
        // Resume Note Button
        if let note = self.note,
           note.isListeningForSpeech &&
            note.userInitiatedPausedListeningForSpeech {
            self.showButton(self.resumeNoteButton)
        } else {
            self.hideButton(self.resumeNoteButton)
        }
        
        // Edit Note Button
        if let note = self.note,
           !note.isListeningForSpeech &&
            note.noteSegments.count > 0 &&
            viewController.listeningPermissionsGranted {
            self.showButton(self.editNoteButton)
        } else {
            self.hideButton(self.editNoteButton)
        }
        
        // Stop Listening Note Button
        if let note = self.note,
           note.isListeningForSpeech && !note.isExporting {
            self.showButton(self.stopListeningNoteButton)
        } else {
            self.hideButton(self.stopListeningNoteButton)
        }
        
        // Play Note Button
        if let note = self.note,
           (!note.isPlayingNote || (note.isPlayingNote && note.pausedPlayingNote) || (note.isPlayingNote && (note.isWalkingNote || note.isRunningNote))) && note.noteSegments.count > 0 && !(selectionCursor.hasSelection && !note.isWalkingNote && !note.isRunningNote) {
            self.showButton(self.playButton)
            
            // Change text
            if selectionCursor.hasSelection {
                let buttonLabel = self.playButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Play Selection"
                }
            } else {
                let buttonLabel = self.playButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Play Note"
                }
            }
        } else {
            self.hideButton(self.playButton)
        }
        
        // Stop Playing Note Button
        if let note = self.note,
           note.isPlayingNote && note.noteSegments.count > 0 && !(AVAudioSession.isHeadphonesConnected && selectionCursor.hasSelection) && !(AVAudioSession.isHeadphonesConnected && note.isWalkingNote) {
            self.showButton(self.stopPlayingButton)
            
            // Change text
            if selectionCursor.hasSelection {
                let buttonLabel = self.stopPlayingButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Stop Selection"
                }
            } else {
                let buttonLabel = self.stopPlayingButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Stop Note"
                }
            }
        } else {
            self.hideButton(self.stopPlayingButton)
        }
        
        // Play Echo Button
        if let note = self.note,
           (!(note.isPlayingEcho || note.isPlayingPassiveEcho) || (note.isPlayingEcho && note.pausedEcho) || (note.isPlayingEcho && (note.isWalkingNote || note.isRunningNote))) && note.noteSegments.count > 0 && !(selectionCursor.hasSelection && !note.isWalkingNote && !note.isRunningNote) {
            self.showButton(self.echoButton)
            
            // Change text
            if selectionCursor.hasSelection {
                let buttonLabel = self.echoButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Echo Selection"
                }
            } else {
                let buttonLabel = self.echoButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Echo Note"
                }
            }
        } else {
            self.hideButton(self.echoButton)
        }

        // Stop Echo Button
        if let note = self.note,
           (note.isPlayingEcho || note.isPlayingPassiveEcho) && note.noteSegments.count > 0 && !(selectionCursor.hasSelection && !note.isWalkingNote && !note.isRunningNote) {
            self.showButton(self.stopEchoButton)
        } else {
            self.hideButton(self.stopEchoButton)
        }
        
        // Export Note Button
        if let note = self.note, note.noteSegments.count > 0 && !note.isListeningForSpeech {
            self.showButton(self.exportButton)
            
            // Change text
            if selectionCursor.hasSelection {
                let buttonLabel = self.exportButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Export Selection"
                }
            } else {
                let buttonLabel = self.exportButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Export Note"
                }
            }
        } else {
            self.hideButton(self.exportButton)
        }
        
        // Walk Element Button
        if let note = self.note, note.noteSegments.count > 0 {
            self.showButton(self.walkButton)
            
            // Change text
            if selectionCursor.hasSelection {
                let buttonLabel = self.walkButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Walk Selection"
                }
            } else {
                let buttonLabel = self.walkButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Walk Note"
                }
            }
        } else {
            self.hideButton(self.walkButton)
        }
        
        // ===== Manage Visibility of Menu Bar =====
    
        if viewController.appActivated {
            self.setMenuBarVisibility(as: true)
        } else {
            self.setMenuBarVisibility(as: false)
        }
    }
    
    func adjustCommandBar() {
        print("===== Adjust Command Bar =====")
        // ===== Number of active buttons =====
        var numActiveButtons = 0
        
        // ===== Resting Command Bar Buttons ======
        
        // Run Note Button
        if let note = self.note, note.noteSegments.count > 0 && !selectionCursor.isUpdatingSelection {
            numActiveButtons += 1
            self.showButton(self.runButton)
            // Change text
            if selectionCursor.hasSelection {
                let buttonLabel = self.runButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Run Selection"
                }
            } else {
                let buttonLabel = self.runButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Run Note"
                }
            }
        } else {
            self.hideButton(self.runButton)
        }
        
        // Pause Note Button
        if let note = self.note, note.noteSegments.count > 0 &&
            (
                (note.isListeningForSpeech && !note.pausedListeningForSpeech) ||
                (note.isPlayingNote && !note.pausedPlayingNote)
            ) && !selectionCursor.hasSelection && !note.isWalkingNote && !note.isRunningNote {
            numActiveButtons += 1
            self.showButton(self.pauseButton)
            // Change text
            if selectionCursor.hasSelection {
                let buttonLabel = self.pauseButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Pause Selection"
                }
            } else {
                let buttonLabel = self.pauseButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Pause Note"
                }
            }
        } else {
            self.hideButton(self.pauseButton)
        }
        
        // Playback Rate Button
        if let note = self.note, note.noteSegments.count > 0 {
            numActiveButtons += 1
            self.showButton(self.playbackRateButton)
        } else {
            self.hideButton(self.playbackRateButton)
        }
        
        // Echo Rate Button
        if let note = self.note, note.noteSegments.count > 0 {
            numActiveButtons += 1
            self.showButton(self.echoRateButton)
        } else {
            self.hideButton(self.echoRateButton)
        }
        
        // ===== Conditional Buttons =====
        
        // Move Here Button
        if let note = self.note, note.isListeningForSpeech && (note.pausedPlayingNote || note.isPlayingNote || note.isPlayingEcho || note.pausedEcho) {
            numActiveButtons += 1
            self.showButton(self.moveHereButton)
        } else {
            self.hideButton(self.moveHereButton)
        }
        
        // Inspect Clipboard Button
        if let note = self.note, let _ = selectionCursor.clipboard, note.isListeningForSpeech {
            numActiveButtons += 1
            self.showButton(self.inspectClipboardButton)
        } else {
            self.hideButton(self.inspectClipboardButton)
        }
        
        // Play Commit Button
        if let note = self.note, note.committedBufferRanges.count > 0 && note.isListeningForSpeech {
            numActiveButtons += 1
            self.showButton(self.playCommitButton)
        } else {
            self.hideButton(self.playCommitButton)
        }
        
        // Pause Echo Button
        if let note = self.note, note.isPlayingEcho && !note.pausedEcho && !selectionCursor.hasSelection && !note.isWalkingNote && !note.isRunningNote {
            numActiveButtons += 1
            self.showButton(self.pauseEchoButton)
        } else {
            self.hideButton(self.pauseEchoButton)
        }
        
        // Skip Backward Button
        if let note = self.note, note.isPlayingNote && !selectionCursor.hasSelection && !note.isWalkingNote && !note.isRunningNote {
            numActiveButtons += 1
            self.showButton(self.skipBackwardButton)
        } else {
            self.hideButton(self.skipBackwardButton)
        }
        
        // Skip Forward Button
        if let note = self.note, note.isPlayingNote && !selectionCursor.hasSelection && !note.isWalkingNote && !note.isRunningNote {
            numActiveButtons += 1
            self.showButton(self.skipForwardButton)
        } else {
            self.hideButton(self.skipForwardButton)
        }
        
        // Previous Walk Element Button
        if let note = self.note, note.isWalkingNote {
            numActiveButtons += 1
            self.showButton(self.walkPreviousElementButton)
        } else {
            self.hideButton(self.walkPreviousElementButton)
        }
        
        // Next Walk Element Button
        if let note = self.note, note.isWalkingNote {
            numActiveButtons += 1
            self.showButton(self.walkNextElementButton)
        } else {
            self.hideButton(self.walkNextElementButton)
        }
        
        // Exit Walk Run Button
        if let note = self.note, note.isWalkingNote || note.isRunningNote  {
            numActiveButtons += 1
            self.showButton(self.exitWalkRunButton)
        } else {
            self.hideButton(self.exitWalkRunButton)
        }
        
        // Halt Run Button
        if let note = self.note, note.isRunningNote {
            numActiveButtons += 1
            self.showButton(self.haltRunButton)
        } else {
            self.hideButton(self.haltRunButton)
        }
        
        // ===== Selection Buttons ======

        // Increase Rate Button
        if let firstSelectionSegment = selectionCursor.selectionSegments?.first, selectionCursor.hasSelection && !selectionCursor.isUpdatingSelection && firstSelectionSegment.getRate() + Utils.DISCRETE_PLAYBACK_DELTA <= Utils.MAXIMUM_PLAYBACK_RATE  {
            numActiveButtons += 1
            self.showButton(self.increaseRateButton)
        } else {
            self.hideButton(self.increaseRateButton)
        }
        
        // Decrease Rate Button
        if let firstSelectionSegment = selectionCursor.selectionSegments?.first, selectionCursor.hasSelection && !selectionCursor.isUpdatingSelection && firstSelectionSegment.getRate() - Utils.DISCRETE_PLAYBACK_DELTA >= Utils.MINIMUM_PLAYBACK_RATE {
            numActiveButtons += 1
            self.showButton(self.decreaseRateButton)
        } else {
            self.hideButton(self.decreaseRateButton)
        }
        
        // Delete Button
        if selectionCursor.hasSelection && !selectionCursor.isUpdatingSelection {
            numActiveButtons += 1
            self.showButton(self.deleteSelectionButton)
        } else {
            self.hideButton(self.deleteSelectionButton)
        }
        
        // Update Button
        if selectionCursor.hasSelection && !selectionCursor.isUpdatingSelection {
            numActiveButtons += 1
            self.showButton(self.updateSelectionButton)
        } else {
            self.hideButton(self.updateSelectionButton)
        }
        
        // Cancel Update Button
        if selectionCursor.hasSelection && selectionCursor.isUpdatingSelection {
            numActiveButtons += 1
            self.showButton(self.cancelUpdateSelectionButton)
        } else {
            self.hideButton(self.cancelUpdateSelectionButton)
        }
        
        // Copy Button
        if selectionCursor.hasSelection && !selectionCursor.isUpdatingSelection {
            numActiveButtons += 1
            self.showButton(self.copySelectionButton)
        } else {
            self.hideButton(self.copySelectionButton)
        }
        
        // Cut Button
        if selectionCursor.hasSelection && !selectionCursor.isUpdatingSelection {
            numActiveButtons += 1
            self.showButton(self.cutSelectionButton)
        } else {
            self.hideButton(self.cutSelectionButton)
        }
        
        // ===== Manage Visibility of CommandBar =====
    
        if numActiveButtons > 0 && viewController.appActivated {
            self.setScrollViewVisibility(as: true)
        } else {
            self.setScrollViewVisibility(as: false)
        }
    }
    
    func handleTransformationsView() {
        if let selectionTransformations = selectionCursor.selectionTransformations, selectionCursor.hasSelection {
            self.transformationLabel?.isHidden = false
            self.transformationLabel?.text = "1.0"
            for transformation in selectionTransformations {
                if transformation.type == .playbackRate, let value = transformation.value {
                    self.transformationLabel?.text = String(value)
                    break
                }
            }
        } else {
            self.transformationLabel?.isHidden = true
        }
    }
    
    
    // MARK: - Entry Methods
    
    func setNote(note: Note) {
        print("===== Detail View: Set Note =====")
        if let note = self.note {
            note.removeObserver(
                self,
                forKeyPath: "isListeningForSpeech",
                context: nil
            )
            
            note.removeObserver(
                self,
                forKeyPath: "pausedListeningForSpeech",
                context: nil
            )
            
            note.removeObserver(
                self,
                forKeyPath: "isWalkingNote",
                context: nil
            )
            
            note.removeObserver(
                self,
                forKeyPath: "isRunningNote",
                context: nil
            )
        }
        
        // Set Note
        self.note = note
        self.note!.setViewController(vc: self)
        
        // Increment Note Views
        self.note!.incrementViewCount()
    }
    
    @objc func deleteNote() {
        print("===== Delete Entry =====")
        guard let note = self.note else {
            print("\t[Error] There was a problem deleting note")
            return
        }
        
        // Play sound
        soundEngine.delete()
        
        // Give haptic feedback
//        hapticEngine.mediumImpact()
        hapticEngine.success()
        
        if note.isPlayingEcho || note.isPlayingPassiveEcho {
            note.stopEcho(omitFeedback: true)
        }
        
        if note.isPlayingNote {
            note.stop()
        }
        
        // Reset Selection Cursor
        selectionCursor.reset()
        
        // Remove previous observer
        note.removeObserver(
            self,
            forKeyPath: "isListeningForSpeech",
            context: nil
        )
        
        note.removeObserver(
            self,
            forKeyPath: "pausedListeningForSpeech",
            context: nil
        )
        
        note.removeObserver(
            self,
            forKeyPath: "isWalkingNote",
            context: nil
        )
        
        note.removeObserver(
            self,
            forKeyPath: "isRunningNote",
            context: nil
        )
        
        // Stop listening for speech
        // Reset note
        if note.isListeningForSpeech {
            note.stopListeningForSpeech() {
                viewController.startListeningForVoiceCommands()
            }
        } else {
            viewController.startListeningForVoiceCommands()
        }
        
        DispatchQueue.main.async {
            self.textView?.attributedText = NSMutableAttributedString(string: "")
            self.navigationItem.rightBarButtonItems = nil
            self.adjustCommandBar()
            self.adjustMenuBar()
            self.setCursorVisibility(as: false)
        }
        
        self.note = nil
        
        // TODO: Kick back to table view
    }
    
    // MARK: - Helper Functions
    
    func showButton(_ commandButton: UIView?) {
        guard let commandButton = commandButton else { return }

        let button = commandButton.subviews.filter {$0 is UIButton }
        if let button = button.first as? UIButton {
            button.isEnabled = true
        }
        
        commandButton.isHidden = false
        
        if commandButton.alpha == 0 {
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    commandButton.alpha = 1
                }
            )
        }
    }
    
    func hideButton(_ commandButton: UIView?) {
        guard let commandButton = commandButton else { return }

        if commandButton.alpha == 1 {
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    commandButton.alpha = 0
                }
            )
        }
        
        Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_VIEW_TRANSITION_DURATION, repeats: false) { timer in
            let button = commandButton.subviews.filter {$0 is UIButton }
            if let button = button.first as? UIButton {
                button.isEnabled = false
            }
            commandButton.isHidden = true
        }
    }
    
    // MARK: - Key-Value Observer
    
    public override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        if keyPath == "selectedTextRange" {
            // Determine if we adjust command bar
            self.adjustCommandBar()
        } else if keyPath == "isListeningForSpeech" {
            if let isListeningForSpeech = change?[.newKey] as? Bool, isListeningForSpeech {
                self.setCursorVisibility(as: isListeningForSpeech)
            } else if let isListeningForSpeech = change?[.newKey] as? Bool, !isListeningForSpeech {
                self.removeCursor()
                self.setCursorVisibility(as: false)
            }
        } else if keyPath == "hasSelection" {
            if let note = self.note, let hasSelection = change?[.newKey] as? Bool, hasSelection && note.isListeningForSpeech {
                print("====== Go from no selection to selection while recording ======")
                // ====== Go from no selection to selection while recording ======
                //
                
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] timer in
                    // Determine if we present adjust rate buttons
                    self!.adjustCommandBar()
                    self!.adjustMenuBar()
                    self!.setCursorVisibility(as: false)
                }
                // Determine if we present transformation information
                self.handleTransformationsView()
                // We show command bar when successfully paused listening for speech
                // stop listening for speech, start listening for commands
                if !note.pausedListeningForSpeech {
                    note.stopListeningForSpeech(pause: true) {
                        viewController.startListeningForVoiceCommands()
                    }
                } else if !viewController.isListeningForCommands {
                    viewController.startListeningForVoiceCommands()
                }
            } else if let note = self.note, let newHasSelection = change?[.newKey] as? Bool, let oldHasSelection = change?[.oldKey] as? Bool, !newHasSelection && oldHasSelection && note.isListeningForSpeech && note.pausedListeningForSpeech && viewController.isListeningForCommands && !note.isPlayingNote && !note.isPlayingEcho && !note.isPlayingPassiveEcho {
                print("====== Go from selection to no selection while recording ======")
                // ====== Go from selection to no selection while recording ======
                //
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] timer in
                    // Determine if we present adjust rate buttons
                    self!.adjustCommandBar()
                    self!.adjustMenuBar()
                    self!.setCursorVisibility(as: true)
                }
                // Determine if we present transformation information
                self.handleTransformationsView()
                // start listening for speech again
                if note.pausedListeningForSpeech {
                    note.startListeningForSpeech()
                }
                
                Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] timer in
                    // Update UI Text in case we have new transformations
                    self!.updateUIText(text: note.getText(), transformations: note.transformations)
                }
            } else if let note = self.note, let hasSelection = change?[.newKey] as? Bool, hasSelection && !note.isListeningForSpeech && viewController.isListeningForCommands {
                print("====== Go from no selection to selection while not recording ======")
                // ====== Go from no selection to selection while not recording ======
                //
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] timer in
                    // Determine if we present adjust rate buttons
                    self!.adjustCommandBar()
                    self!.adjustMenuBar()
                }
                // Determine if we present transformation information
                self.handleTransformationsView()
            } else if let note = self.note, let newHasSelection = change?[.newKey] as? Bool, let oldHasSelection = change?[.oldKey] as? Bool, !newHasSelection && oldHasSelection && !note.isListeningForSpeech && viewController.isListeningForCommands {
                print("====== Go from selection to no selection while not recording ======")
                // ====== Go from selection to no selection while not recording ======
                //
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] timer in
                    // Determine if we present adjust rate buttons
                    self!.adjustCommandBar()
                    self!.adjustMenuBar()
                }
                // Determine if we present transformation information
                self.handleTransformationsView()
            }
        } else if keyPath == "clipboard" {
            if let clipboard = change?[.newKey] as? [NoteSegment]?, let _ = clipboard {
                self.adjustCommandBar()
                self.navigationItem.rightBarButtonItems = [self.getPasteClipboardButton()]
            } else {
                self.adjustCommandBar()
                self.navigationItem.rightBarButtonItems = nil
            }
        } else if keyPath == "isUpdatingSelection" {
            // Determine if we adjust command bar
            self.adjustCommandBar()
            self.adjustMenuBar()
        } else if keyPath == "isPromptingForUpdateAcceptance" {
            // Determine if we adjust command bar
            self.adjustCommandBar()
            self.adjustMenuBar()
        } else if keyPath == "isWalkingNote" {
            // Determine if we adjust command bar
            self.adjustCommandBar()
            self.adjustMenuBar()
        } else if keyPath == "isRunningNote" {
            // Determine if we adjust command bar
            self.adjustCommandBar()
            self.adjustMenuBar()
        }
    }
    
    // MARK: - Touch Events
    
    @objc func handleSingleTap(touch: UITapGestureRecognizer) {
        print("===== Touch Interaction: Single Tap =====")
        if let note = self.note, viewController.appActivated && note.isListeningForSpeech {
            print("\tDetermine text position near touch point...")
            let touchPoint = touch.location(in: self.textView)
            let textPosition = self.textView?.closestPosition(to: touchPoint)
            
            if self.textView?.selectedTextRange != nil && selectionCursor.hasSelection && (note.isWalkingNote || note.isRunningNote) {
                // Remove Selection in view and model
                print("\tPrior selection detected. Remove Selection in view and model...")
                note.exitWalk(withFeedback: false)
            } else if self.textView?.selectedTextRange != nil && selectionCursor.hasSelection {
                // Remove Selection in view and model
                print("\tPrior selection detected. Remove Selection in view and model...")
                selectionCursor.clearSelection()
            }
            
            if let textPosition = textPosition {
                print("\tMove cursor to new position...")
                selectionCursor.moveCursor(textPosition: textPosition, cache: true)
            }
            
            self.adjustCommandBar()
        } else {
            print("\tAborted because app is not active or not listening for speech.")
        }
    }
    
    // Reference: https://www.appsdeveloperblog.com/create-uislider-in-swift-programmatically/
    // Reference: https://stackoverflow.com/questions/25499803/how-to-change-speech-rate-during-speaking-using-avspeechsynthesizer-in-ios-7
    @objc func sliderValueDidChange(_ sender: UISlider!) {
        print("===== Screen Button: Slider Value Changed =====")
        print("\tNew value: \(sender.value)")
        
        if self.sliderType == .playback {
            // Set new playback rate
            viewController.setPlaybackRate(to: sender.value)
            
            if let note = self.note, note.isPlayingNote {
                let _ = Utils.setPlayerRate(player: note.player, rate: sender.value)
            }
        } else if self.sliderType == .echo {
            // Set new echo rate
            if let note = self.note, note.isPlayingEcho || note.isPlayingPassiveEcho {
                // Activate update echo rate flag
                viewController.setEchoRate(to: sender.value, stageUpdate: true)
            } else {
                // Set immediately
                viewController.setEchoRate(to: sender.value)
            }
        }
    }
    
    // MARK: - Menu Bar Methods
    
    @IBAction func startNote(_ sender: Any? = nil) {
        self.handleStartNote()
    }

    func handleStartNote(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Start Note =====")
        } else {
            print("===== Voice Command: Handle Start Note =====")
        }
        
        guard let note = self.note else {
            print("\t[Error] There was a problem executing command. Note not detected.")
            return
        }
        
        if note.isListeningForSpeech {
            Utils.executeError(note: note, text: "Note already started.", voiceCommand: voiceCommand)
        }
        
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        if session.recordPermission != .granted || authStatus != .authorized {
            let dialogActions = [
                DialogAction(title: "Grant Permission", style: .default, handler: { action in
                    viewController.requestPermissions(handler: {
                        viewController.configureListeningForWakePhrase()
                    })
                }),
                DialogAction(title: "Cancel", style: .cancel, handler: nil)
            ]
            
            let dialogItem = DialogItem(
                title: "Speech Recognition Permission Denied",
                message: "Please grant permission for application to initiate speech transcription.",
                preferredStyle: .alert,
                actions: dialogActions
            )
            Utils.presentDialog(dialogItem: dialogItem)
            
            return
        }
        
        if authStatus == .authorized && session.recordPermission == .granted {
            if let note = self.note, !note.isListeningForSpeech && !note.isExporting {
                if !viewController.isListeningForCommands {
                    // User switched off listening with the button
                    // Change button to normal again
                }
                
                if voiceCommand {
                    // Play Sound
                    soundEngine.voiceCommandAccept()
                }
                
                print("\tStarting Note...")
                note.startListeningForSpeech() {
                    DispatchQueue.main.async {
                        self.startRecordingUITimer(recording: true)
                        self.adjustCommandBar()
                        self.adjustMenuBar()
                    }
                }
            } else {
                if note.isListeningForSpeech {
                    Utils.executeError(note: note, text: "Note already started.", voiceCommand: voiceCommand)
                } else {
                    Utils.executeError(note: note, text: "Wait until note export completion.", voiceCommand: voiceCommand)
                }
                print("\t[Error] There was a problem starting note. System does not have record permissions.")
            }
        } else {
            Utils.executeError(note: note, text: "Unable to start note.", voiceCommand: voiceCommand)
            print("\t[Error] There was a problem starting note. System does not have record permissions.")
        }
    }
    
    @IBAction func resumeNote(_ sender: Any? = nil) {
        self.handleResumeNote()
    }
    
    func handleResumeNote(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Resume Note =====")
        } else {
            print("===== Voice Command: Handle Resume Note =====")
        }
        
        guard let note = self.note else {
            print("\t[Error] There was a problem executing command. Note not detected.")
            return
        }
        
        if note.isListeningForSpeech && note.pausedListeningForSpeech && viewController.isListeningForCommands {
            if voiceCommand {
                // Play Sound
                soundEngine.voiceCommandAccept()
            }

            note.startListeningForSpeech() {
                DispatchQueue.main.async {
                    self.startRecordingUITimer(recording: true)
                    self.adjustCommandBar()
                    self.adjustMenuBar()
                    handler?()
                }
            }
        } else {
            Utils.executeError(note: note, text: "No ongoing note.", handler: handler)
            return
        }
    }
    
    @IBAction func editNote(_ sender: Any? = nil) {
        self.handleEditNote()
    }

    func handleEditNote(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Edit Note =====")
        } else {
            print("===== Voice Command: Handle Edit Note =====")
        }
        
        guard let note = self.note else {
            print("\t[Error] There was a problem executing command. Note not detected.")
            return
        }
        
        if note.noteSegments.count == 0 {
            Utils.executeError(note: note, text: "No existing note.", voiceCommand: voiceCommand, handler: handler)
        }
        
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        if session.recordPermission != .granted || authStatus != .authorized {
            let dialogActions = [
                DialogAction(title: "Grant Permission", style: .default, handler: { action in
                    viewController.requestPermissions() {
                        viewController.configureListeningForWakePhrase()
                    }
                }),
                DialogAction(title: "Cancel", style: .cancel, handler: nil)
            ]
            
            let dialogItem = DialogItem(
                title: "Speech Recognition Permission Denied",
                message: "Please grant permission for application to initiate speech transcription.",
                preferredStyle: .alert,
                actions: dialogActions
            )
            Utils.presentDialog(dialogItem: dialogItem)
            
            handler?()
            return
        }
        
        if authStatus == .authorized && session.recordPermission == .granted {
            if !note.isListeningForSpeech && !note.isExporting {
                if voiceCommand {
                    // Play Sound
                    soundEngine.voiceCommandAccept()
                }
                print("\tStarting Note...")
                note.startListeningForSpeech() {
                    DispatchQueue.main.async {
                        self.startRecordingUITimer(recording: true)
                        self.adjustCommandBar()
                        self.adjustMenuBar()
                        handler?()
                    }
                }
            } else {
                Utils.executeError(note: note, text: "Unable to start note.", voiceCommand: voiceCommand, handler: handler)
                print("\t[Error] There was a problem starting note. System does not have record permissions.")
            }
        }
    }
    
    @IBAction func stopListeningNote(_ sender: Any? = nil) {
        self.handleStopListeningNote()
    }
    
    func handleStopListeningNote(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Stop Listening Note =====")
        } else {
            print("===== Voice Command: Stop Listening Note =====")
        }
        
        guard let note = self.note else {
            print("\t[Error] There was a problem executing command. Note not detected.")
            return
        }
        
        if note.isListeningForSpeech && !note.isExporting {
            print("\tStopping Note...")
            if voiceCommand {
                // No sound here
                // We omit sound for stopping note
            }

            note.stopListeningForSpeech() {[weak self] in
                self?.onNoteListenStop!()
                self?.adjustCommandBar()
                self?.adjustMenuBar()
                handler?()
            }
        } else {
            if !note.isListeningForSpeech {
                Utils.executeError(note: note, text: "No ongoing note.", voiceCommand: voiceCommand, handler: handler)
            } else {
                Utils.executeError(note: note, text: "Wait until note export completion.", voiceCommand: voiceCommand, handler: handler)
            }
            print("\t[Error] There was a problem stopping note. We're not listening for speech or are exporting note.")
        }
    }
    
    @IBAction func play(_ sender: Any? = nil) {
        self.handlePlay()
    }
    
    // Should never be called when headphones on while we have a selection
    // Will be looping selection and have isPlayingNote set to true
    // Which should hide playButton
    func handlePlay(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Play \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        } else {
            print("===== Voice Command: Handle Play \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        }
        
        guard let note = self.note else {
            print("\t[Error] There was a problem executing command. Note not detected.")
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let playSegments: (_ segments: [NoteSegment]) -> Void = { segments in
            note.play(
                segments: segments,
                onStartHandler: { [weak self] in
                    // print("Successfully executed playback on start handler")
                    DispatchQueue.main.async {
                        self?.adjustCommandBar()
                        self?.adjustMenuBar()
                    }
                },
                secondElapseHandler: { [weak self] in
                    // print("Successfully executed playback second elapsed handler")
                    DispatchQueue.main.async {
                        if !note.isListeningForSpeech && note.player.currentTime().seconds != Double.infinity && note.player.currentTime().seconds != Double.nan && note.player.currentTime().seconds != -Double.infinity {
                            self?.navigationItem.title = "\(Utils.formattedTime(time: Float(note.player.currentTime().seconds)))/\(Utils.formattedTime(time: Float(note.getDuration(filteredDuration: true).seconds)))"
                        }
                    }
                },
                segmentBoundaryHandler: { [weak self] in
                    // print("Successfully executed playback on segment boundary handler")
                    DispatchQueue.main.async {
                        if let segment = note.getSegment(type: .current), segment.getText().count > 0 && segment.isActive(), let highlightRange = note.getSegmentTextRange(of: segment) {
                            // update text
                            self?.updateUIText(text: note.getText(), highlightRange: highlightRange, transformations: note.transformations)
                        }
                        
                        if let segment = note.getSegment(type: .current), let pitch = segment.getPitch() {
                            // update pitch
                            self?.pitchLabel?.text = pitch.note.string
                        }
                    }
                }, onFinishHandler: { [weak self] in
                    // print("Successfully executed playback on finish handler")
                    DispatchQueue.main.async {
                        self?.updateUIText(text: note.getText(), transformations: note.transformations)
                        if !note.isListeningForSpeech {
                            self?.navigationItem.title = ""
                        }
                        
                        self?.adjustCommandBar()
                        self?.adjustMenuBar()
                        
                        if note.pausedWalkingNote {
                            note.walk() {
                                handler?()
                            }
                        } else if note.pausedRunningNote {
                            note.run() {
                                handler?()
                            }
                        } else {
                            handler?()
                        }
                    }
                }
            )
        }
        
        let executePlay = {
            if note.pausedWalkingNote || note.pausedRunningNote {
                playSegments(Array(note.noteSegments[note.walkingRange!]))
            } else if let selectionSegments = selectionCursor.selectionSegments, selectionCursor.hasSelection {
                playSegments(selectionSegments)
            } else {
                note.play(
                    onStartHandler: { [weak self] in
                        // print("Successfully executed playback on start handler")
                        DispatchQueue.main.async {
                            self?.adjustCommandBar()
                            self?.adjustMenuBar()
                        }
                    },
                    secondElapseHandler: { [weak self] in
                        // print("Successfully executed playback second elapsed handler")
                        DispatchQueue.main.async {
                            if !note.isListeningForSpeech && note.player.currentTime().seconds != Double.infinity && note.player.currentTime().seconds != Double.nan && note.player.currentTime().seconds != -Double.infinity {
                                self?.navigationItem.title = "\(Utils.formattedTime(time: Float(note.player.currentTime().seconds)))/\(Utils.formattedTime(time: Float(note.getDuration(filteredDuration: true).seconds)))"
                            }
                        }
                    },
                    segmentBoundaryHandler: { [weak self] in
                        // print("Successfully executed playback on segment boundary handler")
                        DispatchQueue.main.async {
                            if let segment = note.getSegment(type: .current), segment.getText().count > 0 && segment.isActive(), let highlightRange = note.getSegmentTextRange(of: segment) {
                                // update text
                                self?.updateUIText(text: note.getText(), highlightRange: highlightRange, transformations: note.transformations)
                            }
                            
                            if let segment = note.getSegment(type: .current), let pitch = segment.getPitch() {
                                // update pitch
                                self?.pitchLabel?.text = pitch.note.string
                            }
                        }
                    }, onFinishHandler: { [weak self] in
                        // print("Successfully executed playback on finish handler")
                        DispatchQueue.main.async {
                            self?.updateUIText(text: note.getText(), transformations: note.transformations)
                            if !note.isListeningForSpeech {
                                self?.navigationItem.title = ""
                            }
                            
                            self?.adjustCommandBar()
                            self?.adjustMenuBar()
                            
                            if note.pausedWalkingNote {
                                note.walk() {
                                    handler?()
                                }
                            } else if note.pausedRunningNote {
                                note.run() {
                                    handler?()
                                }
                            } else {
                                handler?()
                            }
                        }
                    }
                )
            }
        }
        
        if note.isWalkingNote || note.isRunningNote {
            note.exitWalk(pause: true, clearSelection: false, withFeedback: false) {
                if note.isPlayingNote {
                    note.stop() {
                        executePlay()
                    }
                } else {
                    executePlay()
                }
            }
        } else if note.isPlayingNote {
            note.stop() {
                executePlay()
            }
        } else {
            executePlay()
        }
    }
    
    @IBAction func stopPlaying(_ sender: Any? = nil) {
        self.handleStopPlaying()
    }

    func handleStopPlaying(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Playing \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        } else {
            print("===== Voice Command: Handle Playing \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        }
        
        guard let note = self.note else {
            print("\t[Error] There was a problem executing command. Note not detected.")
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        // Stop Note
        note.stop() { [weak self] in
            DispatchQueue.main.async {
                self?.adjustCommandBar()
                self?.adjustMenuBar()
                if note.pausedWalkingNote {
                    note.walk() {
                        handler?()
                    }
                } else if note.pausedRunningNote {
                    note.run() {
                        handler?()
                    }
                } else {
                    handler?()
                }
            }
        }
    }
    
    @IBAction func echo(_ sender: Any? = nil) {
        self.handleEcho()
    }
    
    func handleEcho(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("==== Screen Button: Handle Echo \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        } else {
            print("==== Voice Command: Handle Echo \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        }
        
        guard let note = self.note else {
            print("\t[Error] There was a problem executing command. Note not detected.")
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let executeEcho = {
            print("\tSpeech synthesizer \(note.pausedEcho ? "continue" : "starts") speaking...")
            var segments: [NoteSegment]
            if note.pausedWalkingNote || note.pausedRunningNote {
                segments = Array(note.noteSegments[note.walkingRange!])
            } else if selectionCursor.hasSelection {
                segments = selectionCursor.selectionSegments!
            } else {
                segments = note.noteSegments
            }
            note.startEcho(
                segments: segments,
                onStartHandler: { [weak self] in
                    DispatchQueue.main.async {
                        self?.adjustCommandBar()
                        self?.adjustMenuBar()
                    }
                },
                onFinishHandler: { [weak self] in
                    DispatchQueue.main.async {
                        self?.adjustCommandBar()
                        self?.adjustMenuBar()
                        if note.pausedWalkingNote {
                            note.walk() {
                                handler?()
                            }
                        } else if note.pausedRunningNote {
                            note.run() {
                                handler?()
                            }
                        } else {
                            handler?()
                        }
                    }
                }
            )
        }
        
        if note.isWalkingNote || note.isRunningNote {
            note.exitWalk(pause: true, clearSelection: false, withFeedback: false) {
                if note.isPlayingEcho {
                    note.stopEcho() {
                        executeEcho()
                    }
                } else {
                    executeEcho()
                }
            }
        } else if note.isPlayingEcho {
            note.stopEcho() {
                executeEcho()
            }
        } else {
            executeEcho()
        }
    }
    
    @IBAction func stopEcho(_ sender: Any? = nil) {
        self.handleStopEcho()
    }
    
    func handleStopEcho(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Stop Echo =====")
        } else {
            print("===== Voice Command: Handle Stop Echo =====")
        }
        
        guard let note = self.note else {
            print("\t[Error] There was a problem executing command. Note not detected.")
            return
        }
        
        if !note.isPlayingEcho && !note.isPlayingPassiveEcho {
            Utils.executeError(note: note, text: "Note not being echoed.", handler: handler)
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        if note.isPlayingEcho || note.isPlayingPassiveEcho {
            note.stopEcho() { [weak self] in
                DispatchQueue.main.async {
                    self?.adjustCommandBar()
                    self?.adjustMenuBar()
                    if note.pausedWalkingNote {
                        note.walk() {
                            handler?()
                        }
                    } else if note.pausedRunningNote {
                        note.run() {
                            handler?()
                        }
                    } else {
                        handler?()
                    }
                }
            }
        }
    }
    
    @IBAction func walk(_ sender: Any? = nil) {
        self.handleWalk()
    }
    
    func handleWalk(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Walk \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        } else {
            print("===== Voice Command: Handle Walk \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        }
        
        guard let note = self.note else {
            print("\t[Error] There was a problem executing command. Note not detected.")
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        if let selectionSegments = selectionCursor.selectionSegments, selectionCursor.hasSelection {
            // Walk Selection
            note.walk(segments: selectionSegments, onStartHandler: handler)
        } else {
            // Walk Note
            note.walk(onStartHandler: handler)
        }
    }
    
    @IBAction func export(_ sender: Any? = nil) {
        self.handleExport()
    }
    
    func handleExport(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Export \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        } else {
            print("===== Voice Command: Handle Export \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        if selectionCursor.hasSelection {
            // Export Selection
        } else {
            // Export Note
        }
        
        // Give haptic feedback
//        hapticEngine.mediumImpact()
        hapticEngine.success()
        
        handler?()
    }
    
    // MARK: - Resting Command Bar Methods
    
    @IBAction func moveHere(_ sender: Any? = nil) {
        self.handleMoveHere()
    }
    
    func handleMoveHere(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Move Here =====")
        } else {
            print("===== Voice Command: Handle Move Here =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        // Give haptic feedback
//        hapticEngine.mediumImpact()
        hapticEngine.success()
        
        handler?()
    }
    
    @IBAction func run(_ sender: Any? = nil) {
        self.handleRun()
    }
    
    func handleRun(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Run \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        } else {
            print("===== Voice Command: Handle Run \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        }
        
        guard let note = self.note else {
            print("\t[Error] There was a problem executing command. Note not detected.")
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        if let selectionSegments = selectionCursor.selectionSegments, selectionCursor.hasSelection {
            // Run Selection
            note.run(segments: selectionSegments, onStartHandler: handler)
        } else {
            // Run Note
            note.run(onStartHandler: handler)
        }
    }
    
    @IBAction func pause(_ sender: Any? = nil) {
        self.handlePause()
    }
    
    func handlePause(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Pause \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        } else {
            print("===== Voice Command: Handle Pause \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        }
        
        guard let note = self.note else {
            print("\t[Error] There was a problem executing command. Note not detected.")
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        if note.isPlayingNote {
            print("\tPausing Playing Note...")
            note.pause() {
                DispatchQueue.main.async {
                    self.adjustCommandBar()
                    self.adjustMenuBar()
                    handler?()
                }
            }
        } else if note.isListeningForSpeech {
            print("\tPausing Listening Note....")
            note.pauseListeningForSpeech() {
                viewController.startListeningForVoiceCommands() {
                    DispatchQueue.main.async {
                        self.adjustCommandBar()
                        self.adjustMenuBar()
                        handler?()
                    }
                }
            }
        } else {
            print("\tUnhandled Branch")
        }
    }
    
    @IBAction func playCommit(_ sender: Any? = nil) {
        self.handlePlayCommit()
    }
    
    func handlePlayCommit(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Play Commit =====")
        } else {
            print("===== Voice Command: Handle Play Commit =====")
        }
        
        guard let note = self.note else {
            print("\t[Error] There was a problem executing command. Note not detected.")
            return
        }
        
        if note.committedBufferRanges.count == 0 {
            Utils.executeError(note: note, text: "No previous commits.", handler: handler)
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let executePlay = {
            let commit = note.getLastCommit()
            print("\tLast Commit: ", note.getText(segments: commit))
            guard let lastCommit = commit else {
                Utils.executeError(note: note, text: "Unable to find last commit.", handler: handler)
                return
            }
            let fromTime = lastCommit.first!.timeMapping.target.start
            let toTime = lastCommit.last!.timeMapping.target.end
            
            note.play(
                from: fromTime,
                to: toTime,
                onStartHandler: { [weak self] in
                    // print("Successfully executed playback on start handler")
                    DispatchQueue.main.async {
                        self?.adjustCommandBar()
                        self?.adjustMenuBar()
                    }
                },
                secondElapseHandler: { [weak self] in
                    // print("Successfully executed playback second elapsed handler")
                    DispatchQueue.main.async {
                        if !note.isListeningForSpeech && note.player.currentTime().seconds != Double.infinity && note.player.currentTime().seconds != Double.nan && note.player.currentTime().seconds != -Double.infinity {
                            self?.navigationItem.title = "\(Utils.formattedTime(time: Float(note.player.currentTime().seconds)))/\(Utils.formattedTime(time: Float(note.getDuration(filteredDuration: true).seconds)))"
                        }
                    }
                },
                segmentBoundaryHandler: { [weak self] in
                    // print("Successfully executed playback on segment boundary handler")
                    DispatchQueue.main.async {
                        if let segment = note.getSegment(type: .current), segment.getText().count > 0 && segment.isActive(), let highlightRange = note.getSegmentTextRange(of: segment) {
                            // update text
                            self?.updateUIText(text: note.getText(), highlightRange: highlightRange, transformations: note.transformations)
                        }
                        
                        if let segment = note.getSegment(type: .current), let pitch = segment.getPitch() {
                            // update pitch
                            self?.pitchLabel?.text = pitch.note.string
                        }
                    }
                }, onFinishHandler: { [weak self] in
                    // print("Successfully executed playback on finish handler")
                    DispatchQueue.main.async {
                        self?.updateUIText(text: note.getText(), transformations: note.transformations)
                        if !note.isListeningForSpeech {
                            self?.navigationItem.title = ""
                        }
                        
                        self?.adjustCommandBar()
                        self?.adjustMenuBar()
                        if note.pausedWalkingNote {
                            note.walk() {
                                handler?()
                            }
                        } else if note.pausedRunningNote {
                            note.run() {
                                handler?()
                            }
                        } else {
                            handler?()
                        }
                    }
                }
            )
        }
        
        if note.isWalkingNote || note.isRunningNote {
            note.exitWalk(pause: true, clearSelection: false, withFeedback: false) {
                if note.isPlayingNote {
                    note.stop() {
                        executePlay()
                    }
                } else {
                    executePlay()
                }
            }
        } else if note.isPlayingNote {
            note.stop() {
                executePlay()
            }
        } else {
            executePlay()
        }
    }
    
    @IBAction func pauseEcho(_ sender: Any? = nil) {
        self.handlePauseEcho()
    }
    
    func handlePauseEcho(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Pause Echo =====")
        } else {
            print("===== Voice Command: Handle Pause Echo =====")
        }
        
        guard let note = self.note else {
            print("\t[Error] There was a problem executing command. Note not detected.")
            return
        }
        
        if !note.isPlayingEcho {
            Utils.executeError(note: note, text: "Note not being echoed.", handler: handler)
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        note.pauseEcho() {
            self.adjustCommandBar()
            self.adjustMenuBar()
            
            if viewController.pausedListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                // when headphones are off we don't listen for voice commands while echoing
                // but on completion we turn it back on
                viewController.startListeningForVoiceCommands() {
                    DispatchQueue.main.async {
                        self.adjustCommandBar()
                        self.adjustMenuBar()
                        handler?()
                    }
                }
            } else if note.pausedListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                // when headphones are off we don't listen for speech while echoing
                // but on completion we turn it back on
                note.startListeningForSpeech() {
                    DispatchQueue.main.async {
                        self.startRecordingUITimer(recording: true)
                        self.adjustCommandBar()
                        self.adjustMenuBar()
                        handler?()
                    }
                }
            }
        }
    }
    
    @IBAction func inspectClipboard(_ sender: Any? = nil) {
        self.handleInspectClipboard()
    }
    
    func handleInspectClipboard(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Inspect Clipboard:  \(selectionCursor.clipboardText ?? "nil") =====")
        } else {
            print("===== Voice Command: Handle Inspect Clipboard:  \(selectionCursor.clipboardText ?? "nil") =====")
        }
        
        guard let note = self.note else {
            print("\t[Error] There was a problem executing command. Note not detected.")
            return
        }
        
        if let clipboardSelection = selectionCursor.clipboard, clipboardSelection.count > 0 {
            if voiceCommand {
                // Play Sound
                soundEngine.voiceCommandAccept()
            }

            let executePlay = {
                let selectionDuration = CMTimeSubtract(
                    clipboardSelection.last!.timeMapping.target.start,
                    clipboardSelection.first!.timeMapping.target.end
                )
                note.play(
                    segments: clipboardSelection,
                    onStartHandler: { [weak self] in
                        // print("Successfully executed playback on start handler")
                        DispatchQueue.main.async {
                            self?.adjustCommandBar()
                            self?.adjustMenuBar()
                        }
                    },
                    secondElapseHandler: { [weak self] in
                        // print("Successfully executed playback second elapsed handler")
                        DispatchQueue.main.async {
                            if !note.isListeningForSpeech && note.player.currentTime().seconds != Double.infinity && note.player.currentTime().seconds != Double.nan && note.player.currentTime().seconds != -Double.infinity {
                                self?.navigationItem.title = "\(Utils.formattedTime(time: Float(note.player.currentTime().seconds)))/\(Utils.formattedTime(time: Float(selectionDuration.seconds)))"
                            }
                        }
                    }, onFinishHandler: { [weak self] in
                        // print("Successfully executed playback on finish handler")
                        DispatchQueue.main.async {
                            self?.updateUIText(text: note.getText(), transformations: note.transformations)
                            if !note.isListeningForSpeech {
                                self?.navigationItem.title = ""
                            }
                            
                            self?.adjustCommandBar()
                            self?.adjustMenuBar()
                            if note.pausedWalkingNote {
                                note.walk() {
                                    handler?()
                                }
                            } else if note.pausedRunningNote {
                                note.run() {
                                    handler?()
                                }
                            } else {
                                handler?()
                            }
                        }
                    }
                )
            }
            
            if note.isWalkingNote || note.isRunningNote {
                note.exitWalk(pause: true, clearSelection: false, withFeedback: false) {
                    if note.isPlayingNote {
                        note.stop() {
                            executePlay()
                        }
                    } else {
                        executePlay()
                    }
                }
            } else if note.isPlayingNote {
                note.stop() {
                    executePlay()
                }
            } else {
                executePlay()
            }
        } else {
            // havent recorded anything
            Utils.executeError(note: note, text:  "Clipboard is empty.", handler: handler)
            return
        }
    }
    
    @IBAction func skipBackward(_ sender: Any? = nil) {
        self.handleSkipBackward()
    }
    
    func handleSkipBackward(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Skip Backward =====")
        } else {
            print("===== Voice Command: Handle Skip Backward =====")
        }
        
        guard let note = self.note else {
            print("\t[Error] There was a problem executing command. Note not detected.")
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let currentSegment = note.getSegment(type: .current)
        
        if let currentSegment = currentSegment, note.isPlayingNote, CMTimeMake(
            value: Int64(Note.defaultSegmentTimescale * (currentSegment.timeMapping.target.start.seconds - Utils.SKIP_PLAYBACK_DURATION)),
            timescale: Int32(Note.defaultSegmentTimescale)
        ) > CMTime.zero {
            let time = CMTimeMake(
                value: Int64(Note.defaultSegmentTimescale * (currentSegment.timeMapping.target.start.seconds - Utils.SKIP_PLAYBACK_DURATION)),
                timescale: Int32(Note.defaultSegmentTimescale)
            )
            note.skip(to: time)
        } else if let currentSegment = currentSegment, note.isPlayingNote, CMTimeMake(
            value: Int64(Note.defaultSegmentTimescale * (currentSegment.timeMapping.target.start.seconds - Utils.SKIP_PLAYBACK_DURATION)),
            timescale: Int32(Note.defaultSegmentTimescale)
        ) <= CMTime.zero {
            // Will skip past end of track
            Utils.executeError(note: note, text: "Skipping would exceed duration", handler: handler)
        }
        
        handler?()
    }
    
    @IBAction func skipForward(_ sender: Any? = nil) {
        self.handleSkipForward()
    }
    
    func handleSkipForward(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Skip Forward =====")
        } else {
            print("===== Voice Command: Handle Skip Forward =====")
        }
        
        guard let note = self.note else {
            print("\t[Error] There was a problem executing command. Note not detected.")
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let currentSegment = note.getSegment(type: .current)
        
        if let currentSegment = currentSegment, let currentItem = note.player.currentItem, note.isPlayingNote, CMTimeMake(
            value: Int64(Note.defaultSegmentTimescale * (currentSegment.timeMapping.target.start.seconds + Utils.SKIP_PLAYBACK_DURATION)),
            timescale: Int32(Note.defaultSegmentTimescale)
        ) < currentItem.duration {
            let time = CMTimeMake(
                value: Int64(Note.defaultSegmentTimescale * (currentSegment.timeMapping.target.start.seconds + Utils.SKIP_PLAYBACK_DURATION)),
                timescale: Int32(Note.defaultSegmentTimescale)
            )
            note.skip(to: time)
        } else if let currentSegment = currentSegment, let currentItem = note.player.currentItem, note.isPlayingNote, CMTimeMake(
            value: Int64(Note.defaultSegmentTimescale * (currentSegment.timeMapping.target.start.seconds + Utils.SKIP_PLAYBACK_DURATION)),
            timescale: Int32(Note.defaultSegmentTimescale)
        ) >= currentItem.duration {
            // Will skip past end of track
            Utils.executeError(note: note, text: "Skipping would exceed duration", handler: handler)
        }
        
        handler?()
    }
    
    @IBAction func playbackRate(_ sender: Any? = nil) {
        self.handlePlaybackRate()
    }
    
    func handlePlaybackRate(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Playback Rate =====")
        } else {
            print("===== Voice Command: Handle Playback Rate =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        print("\tAdjusting flag to: true")
        self.sliderIsVisible = true
        self.sliderType = .playback
        
        print("\tSet Slider Min and Max Values...")
        self.slider?.minimumValue = Utils.MINIMUM_PLAYBACK_RATE
        self.slider?.maximumValue = Utils.MAXIMUM_PLAYBACK_RATE
        self.slider?.value = viewController.playbackRate
        
        print("\tHide Command Bar...")
        self.setCommandBarVisibility(as: false)
        self.adjustCommandBar()
        
        print("\tShow Slider View...")
        Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_VIEW_TRANSITION_DURATION, repeats: false) {[weak self] timer in
            self!.setSliderVisibility(as: true)
        }
        
        // Give haptic feedback
//        hapticEngine.mediumImpact()
        hapticEngine.success()
        
        handler?()
    }
    
    @IBAction func echoRate(_ sender: Any? = nil) {
        self.handleEchoRate()
    }
    
    func handleEchoRate(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Echo Rate =====")
        } else {
            print("===== Voice Command: Handle Echo Rate =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        print("\tAdjusting flag to: true")
        self.sliderIsVisible = true
        self.sliderType = .echo
        
        print("\tSet Slider Min and Max Values...")
        self.slider?.minimumValue = Utils.MINIMUM_ECHO_RATE
        self.slider?.maximumValue = Utils.MAXIMUM_ECHO_RATE
        self.slider?.value = viewController.echoRate
        
        print("\tHide Command Bar...")
        self.setCommandBarVisibility(as: false)
        self.adjustCommandBar()
        
        print("\tShow Slider View...")
        Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_VIEW_TRANSITION_DURATION, repeats: false) { [weak self] timer in
            self!.setSliderVisibility(as: true)
        }
        
        // Give haptic feedback
//        hapticEngine.mediumImpact()
        hapticEngine.success()
        
        handler?()
    }
    
    @IBAction func exitSlider(_ sender: Any? = nil) {
        self.handleExitSlider()
    }
    
    func handleExitSlider(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Exit Slider =====")
        } else {
            print("===== Voice Command: Handle Exit Slider =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        // Present Feedback
        if self.sliderType == .playback {
            Utils.executeFeedback(
                visualMessage: "Playback Rate: \(viewController.playbackRate)x",
                audioMessage: "Set playback rate to \(viewController.playbackRate)x.",
                withHaptics: true
            )
        } else {
            Utils.executeFeedback(
                visualMessage: "Echo rate: \(viewController.echoRate)x",
                audioMessage: "Set echo rate to \(viewController.echoRate)x.",
                withHaptics: true
            )
        }
        
        print("\tAdjusting flag to: false")
        self.sliderIsVisible = false
        self.sliderType = nil
        
        print("\tHide Slider View...")
        self.setSliderVisibility(as: false)
        
        print("\tShow Command Bar...")
        Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_VIEW_TRANSITION_DURATION, repeats: false) { [weak self] timer in
            self!.setCommandBarVisibility(as: true)
            self!.adjustCommandBar()
        }
        
        // Give haptic feedback
//        hapticEngine.mediumImpact()
        hapticEngine.success()
        
        handler?()
    }
    
    @IBAction func walkNextElement(_ sender: Any? = nil) {
        self.handleWalkNextElement()
    }
    
    func handleWalkNextElement(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Walk Next Element =====")
        } else {
            print("===== Voice Command: Handle Walk Next Element =====")
        }
        
        guard let note = self.note else {
            print("\t[Error] There was a problem executing command. Note not detected.")
            return
        }
        
        if !note.isWalkingNote {
            Utils.executeError(note: note, text: "Not walking note or selection.", handler: handler)
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        note.walkToNextSegment(handler: handler)

        handler?()
    }
    
    @IBAction func walkPreviousElement(_ sender: Any? = nil) {
        self.handleWalkPreviousElement()
    }
    
    func handleWalkPreviousElement(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Walk Previous Element =====")
        } else {
            print("===== Voice Command: Handle Walk Previous Element =====")
        }
        
        guard let note = self.note else {
            print("\t[Error] There was a problem executing command. Note not detected.")
            return
        }
        
        if !note.isWalkingNote {
            Utils.executeError(note: note, text: "Not walking note or selection.", handler: handler)
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        note.walkToPreviousSegment(handler: handler)
        
        handler?()
    }
    
    @IBAction func haltRun(_ sender: Any? = nil) {
        self.handleHaltRun()
    }
    
    func handleHaltRun(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Halt Run =====")
        } else {
            print("===== Voice Command: Handle Halt Run =====")
        }
        
        guard let note = self.note else {
            print("\t[Error] There was a problem executing command. Note not detected.")
            return
        }
        
        if !note.isRunningNote {
            Utils.executeError(note: note, text: "Not running note or selection.", handler: handler)
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        note.haltRun(handler: handler)
        
        handler?()
    }
    
    @IBAction func exitWalkRun(_ sender: Any? = nil) {
        self.handleExitWalkRun()
    }
    
    func handleExitWalkRun(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Exit Walk or Run =====")
        } else {
            print("===== Voice Command: Handle Exit Walk or Run =====")
        }
        
        guard let note = self.note else {
            print("\t[Error] There was a problem executing command. Note not detected.")
            return
        }
        
        if !note.isWalkingNote && !note.isRunningNote {
            Utils.executeError(note: note, text: "Not walking or running note or selection.", handler: handler)
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        note.exitWalk(handler: handler)
    }

    // MARK: - Selection Methods

    @IBAction func increaseRateSelection(_ sender: Any? = nil) {
        self.handleIncreaseRateSelection()
    }

    func handleIncreaseRateSelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Increase Rate Selection: \(selectionCursor.selectionText ?? "nil") =====")
        } else {
            print("===== Voice Command: Increase Rate Selection: \(selectionCursor.selectionText ?? "nil") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        selectionCursor.adjustRateSelection(direction: .up)
        // Determine if we present adjust rate buttons
        self.adjustCommandBar()
        // Update transformation view
        self.handleTransformationsView()
        
        handler?()
    }
    
    @IBAction func decreaseRateSelection(_ sender: Any? = nil) {
        self.handleDecreaseRateSelection()
    }
    
    func handleDecreaseRateSelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Decrease Rate Selection: \(selectionCursor.selectionText ?? "nil") =====")
        } else {
            print("===== Voice Command: Decrease Rate Selection: \(selectionCursor.selectionText ?? "nil") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        selectionCursor.adjustRateSelection(direction: .down)
        // Determine if we present adjust rate buttons
        self.adjustCommandBar()
        // Update transformation view
        self.handleTransformationsView()
        
        handler?()
    }
    
    @IBAction func deleteSelection(_ sender: Any? = nil) {
        self.handleDeleteSelection()
    }

    func handleDeleteSelection(voiceCommand: Bool = false, isCommit: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Delete \(isCommit ? "Commit" : "Selection"): \(selectionCursor.selectionText ?? "nil") =====")
        } else {
            print("===== Voice Command: Handle Delete \(isCommit ? "Commit" : "Selection"): \(selectionCursor.selectionText ?? "nil") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        selectionCursor.deleteSelection(isCommit: isCommit, handler: handler)
    }
    
    @IBAction func updateSelection(_ sender: Any? = nil) {
        self.handleUpdateSelection()
    }
    
    func handleUpdateSelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Update Selection: \(selectionCursor.selectionText ?? "nil") =====")
        } else {
            print("===== Voice Command: Handle Update Selection: \(selectionCursor.selectionText ?? "nil") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        // Turn on ambient track
        if !soundEngine.isPlayingModalAmbience {
            soundEngine.startModalAmbience()
        }
        
        // Execute update selection
        selectionCursor.initiateUpdateSelection()

        // Determine if we present adjust rate buttons
        self.adjustCommandBar()
        
        handler?()
    }
    
    @IBAction func cancelUpdateSelection(_ sender: Any? = nil) {
        self.handleCancelUpdateSelection()
    }
    
    func handleCancelUpdateSelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Cancel Update Selection: \(selectionCursor.selectionText ?? "nil") =====")
        } else {
            print("===== Voice Command: Handle Cancel Update Selection: \(selectionCursor.selectionText ?? "nil") =====")
        }
        
        guard let note = self.note else {
            print("\t[Error] There was a problem executing command. Note not detected.")
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        // Turn off ambient track
        soundEngine.stopModalAmbience()
        
        // Clear buffer segments
        print("\tClearing note buffer...")
        note.clearBuffer()
        
        // Cancel Update Selection
        selectionCursor.cancelUpdateSelection()
        
        // Determine if we present adjust rate buttons
        self.adjustCommandBar()

        handler?()
    }
    
    @IBAction func copySelection(_ sender: Any? = nil) {
        self.handleCopySelection()
    }

    func handleCopySelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Copy Selection: \(selectionCursor.selectionText ?? "nil") =====")
        } else {
            print("===== Voice Command: Handle Copy Selection: \(selectionCursor.selectionText ?? "nil") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        selectionCursor.copySelection()
        
        handler?()
    }
    
    @IBAction func cutSelection(_ sender: Any? = nil) {
        self.handleCutSelection()
    }
    
    func handleCutSelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Cut Selection: \(selectionCursor.selectionText ?? "nil") =====")
        } else {
            print("===== Voice Command: Handle Cut Selection: \(selectionCursor.selectionText ?? "nil") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        selectionCursor.cutSelection()
        
        handler?()
    }
    
    // Reference: https://stackoverflow.com/questions/43251708/passing-arguments-to-selector-in-swift
    @objc func pasteClipboard(_ sender: Any? = nil) {
        self.handlePasteClipboard()
    }
    
    func handlePasteClipboard(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Paste Selection: \(selectionCursor.clipboardText ?? "nil") =====")
        } else {
            print("===== Voice Command: Handle Paste Selection: \(selectionCursor.clipboardText ?? "nil") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        selectionCursor.pasteSelection()

        handler?()
    }
    
    @IBAction func exportSelection(_ sender: Any? = nil) {
        self.handleExportSelection()
    }

    func handleExportSelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Export Selection: \(selectionCursor.selectionText ?? "nil") =====")
        } else {
            print("===== Voice Command: Handle Export Selection: \(selectionCursor.selectionText ?? "nil") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        selectionCursor.exportSelection()
        
        // Give haptic feedback
//        hapticEngine.mediumImpact()
        hapticEngine.success()
        
        handler?()
    }
}
