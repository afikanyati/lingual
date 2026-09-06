# Swift source review

Every source line has one review owner in [native-source-audit.json](native-source-audit.json). The audit validates the file inventory, source hashes, continuous line ranges, decisions and existing React/test targets. It includes blank lines, comments, native scaffolding and inactive experiments. **Review coverage is not feature parity or test coverage.**

Reviewed inventory: 125 Swift files, 36,092 lines. Unreviewed: 0. Lines in units with remaining gaps: 0.

Status meanings: `adapted` maps behavior to browser APIs with the stated differences; `implemented` has a direct counterpart; `support` is platform/diagnostic infrastructure; `inactive` is an unused experiment or disabled path; `native-test` is test scaffolding; `gap` is incomplete or not yet sufficiently verified.

Run `yarn test:source-audit` to detect stale or missing review decisions. `python3 scripts/native-source-audit.py --require-parity` additionally fails while any recorded gap remains. Neither command substitutes for behavioral tests or physical microphone/headphone review.

## File inventory

| Swift source | Lines | Gap units |
| --- | ---: | ---: |
| [diction-processor/AVMutableCompositionTrack+Sentence.swift](../diction-processor/AVMutableCompositionTrack+Sentence.swift) | 27 | 0 |
| [diction-processor/AppDelegate.swift](../diction-processor/AppDelegate.swift) | 78 | 0 |
| [diction-processor/DebugOptions.swift](../diction-processor/DebugOptions.swift) | 27 | 0 |
| [diction-processor/DetailViewController.swift](../diction-processor/DetailViewController.swift) | 2461 | 0 |
| [diction-processor/DictionaryViewController.swift](../diction-processor/DictionaryViewController.swift) | 1674 | 0 |
| [diction-processor/Entry.swift](../diction-processor/Entry.swift) | 4800 | 0 |
| [diction-processor/EntryListManager.swift](../diction-processor/EntryListManager.swift) | 1189 | 0 |
| [diction-processor/EntryManager.swift](../diction-processor/EntryManager.swift) | 3943 | 0 |
| [diction-processor/EntrySegment.swift](../diction-processor/EntrySegment.swift) | 1458 | 0 |
| [diction-processor/EntryTableViewController.swift](../diction-processor/EntryTableViewController.swift) | 1190 | 0 |
| [diction-processor/HapticEngine.swift](../diction-processor/HapticEngine.swift) | 71 | 0 |
| [diction-processor/NotificationEngine.swift](../diction-processor/NotificationEngine.swift) | 391 | 0 |
| [diction-processor/PitchRecognitionEngine.swift](../diction-processor/PitchRecognitionEngine.swift) | 207 | 0 |
| [diction-processor/SceneDelegate.swift](../diction-processor/SceneDelegate.swift) | 153 | 0 |
| [diction-processor/SelectionCursor.swift](../diction-processor/SelectionCursor.swift) | 2784 | 0 |
| [diction-processor/SoundEffectEngine.swift](../diction-processor/SoundEffectEngine.swift) | 367 | 0 |
| [diction-processor/SpeechPlayerEngine.swift](../diction-processor/SpeechPlayerEngine.swift) | 1287 | 0 |
| [diction-processor/SpeechRecognitionEngine.swift](../diction-processor/SpeechRecognitionEngine.swift) | 2334 | 0 |
| [diction-processor/SpeechSynthesisEngine.swift](../diction-processor/SpeechSynthesisEngine.swift) | 758 | 0 |
| [diction-processor/StateManager.swift](../diction-processor/StateManager.swift) | 1060 | 0 |
| [diction-processor/StorageManager.swift](../diction-processor/StorageManager.swift) | 1017 | 0 |
| [diction-processor/UIManager.swift](../diction-processor/UIManager.swift) | 296 | 0 |
| [diction-processor/Utils.swift](../diction-processor/Utils.swift) | 2451 | 0 |
| [diction-processor/VoiceCommandEngine.swift](../diction-processor/VoiceCommandEngine.swift) | 2147 | 0 |
| [diction-processor/beethoven/Array+Extensions.swift](../diction-processor/beethoven/Array+Extensions.swift) | 10 | 0 |
| [diction-processor/beethoven/BarycentricEstimator.swift](../diction-processor/beethoven/BarycentricEstimator.swift) | 21 | 0 |
| [diction-processor/beethoven/Buffer.swift](../diction-processor/beethoven/Buffer.swift) | 17 | 0 |
| [diction-processor/beethoven/Config.swift](../diction-processor/beethoven/Config.swift) | 17 | 0 |
| [diction-processor/beethoven/EstimationError.swift](../diction-processor/beethoven/EstimationError.swift) | 6 | 0 |
| [diction-processor/beethoven/EstimationFactory.swift](../diction-processor/beethoven/EstimationFactory.swift) | 26 | 0 |
| [diction-processor/beethoven/EstimationStrategy.swift](../diction-processor/beethoven/EstimationStrategy.swift) | 10 | 0 |
| [diction-processor/beethoven/Estimator.swift](../diction-processor/beethoven/Estimator.swift) | 31 | 0 |
| [diction-processor/beethoven/FFTTransformer.swift](../diction-processor/beethoven/FFTTransformer.swift) | 54 | 0 |
| [diction-processor/beethoven/HPSEstimator.swift](../diction-processor/beethoven/HPSEstimator.swift) | 50 | 0 |
| [diction-processor/beethoven/InputSignalTracker.swift](../diction-processor/beethoven/InputSignalTracker.swift) | 111 | 0 |
| [diction-processor/beethoven/JainsEstimator.swift](../diction-processor/beethoven/JainsEstimator.swift) | 25 | 0 |
| [diction-processor/beethoven/LocationEstimator.swift](../diction-processor/beethoven/LocationEstimator.swift) | 16 | 0 |
| [diction-processor/beethoven/MaxValueEstimator.swift](../diction-processor/beethoven/MaxValueEstimator.swift) | 5 | 0 |
| [diction-processor/beethoven/OutputSignalTracker.swift](../diction-processor/beethoven/OutputSignalTracker.swift) | 69 | 0 |
| [diction-processor/beethoven/PitchEngine.swift](../diction-processor/beethoven/PitchEngine.swift) | 152 | 0 |
| [diction-processor/beethoven/QuadradicEstimator.swift](../diction-processor/beethoven/QuadradicEstimator.swift) | 16 | 0 |
| [diction-processor/beethoven/QuinnsFirstEstimator.swift](../diction-processor/beethoven/QuinnsFirstEstimator.swift) | 28 | 0 |
| [diction-processor/beethoven/QuinnsSecondEstimator.swift](../diction-processor/beethoven/QuinnsSecondEstimator.swift) | 37 | 0 |
| [diction-processor/beethoven/SignalTracker.swift](../diction-processor/beethoven/SignalTracker.swift) | 23 | 0 |
| [diction-processor/beethoven/SimpleTransformer.swift](../diction-processor/beethoven/SimpleTransformer.swift) | 16 | 0 |
| [diction-processor/beethoven/SimulatorSignalTracker.swift](../diction-processor/beethoven/SimulatorSignalTracker.swift) | 100 | 0 |
| [diction-processor/beethoven/Transformer.swift](../diction-processor/beethoven/Transformer.swift) | 5 | 0 |
| [diction-processor/beethoven/YINEstimator.swift](../diction-processor/beethoven/YINEstimator.swift) | 32 | 0 |
| [diction-processor/beethoven/YINTransformer.swift](../diction-processor/beethoven/YINTransformer.swift) | 19 | 0 |
| [diction-processor/beethoven/YINUtil.swift](../diction-processor/beethoven/YINUtil.swift) | 226 | 0 |
| [diction-processor/data-structures/AudioDeviceDatum.swift](../diction-processor/data-structures/AudioDeviceDatum.swift) | 47 | 0 |
| [diction-processor/data-structures/Caret.swift](../diction-processor/data-structures/Caret.swift) | 35 | 0 |
| [diction-processor/data-structures/Determiners.swift](../diction-processor/data-structures/Determiners.swift) | 28 | 0 |
| [diction-processor/data-structures/DialogAction.swift](../diction-processor/data-structures/DialogAction.swift) | 19 | 0 |
| [diction-processor/data-structures/DialogItem.swift](../diction-processor/data-structures/DialogItem.swift) | 17 | 0 |
| [diction-processor/data-structures/DictionaryAction.swift](../diction-processor/data-structures/DictionaryAction.swift) | 21 | 0 |
| [diction-processor/data-structures/DictionaryLine.swift](../diction-processor/data-structures/DictionaryLine.swift) | 14 | 0 |
| [diction-processor/data-structures/DictionarySection.swift](../diction-processor/data-structures/DictionarySection.swift) | 24 | 0 |
| [diction-processor/data-structures/DictionaryViewTableCell.swift](../diction-processor/data-structures/DictionaryViewTableCell.swift) | 18 | 0 |
| [diction-processor/data-structures/DictionaryViewTableHeader.swift](../diction-processor/data-structures/DictionaryViewTableHeader.swift) | 83 | 0 |
| [diction-processor/data-structures/EntrySnapshot.swift](../diction-processor/data-structures/EntrySnapshot.swift) | 71 | 0 |
| [diction-processor/data-structures/EntryTransformation.swift](../diction-processor/data-structures/EntryTransformation.swift) | 75 | 0 |
| [diction-processor/data-structures/LinkedList.swift](../diction-processor/data-structures/LinkedList.swift) | 102 | 0 |
| [diction-processor/data-structures/MicrophoneDatum.swift](../diction-processor/data-structures/MicrophoneDatum.swift) | 56 | 0 |
| [diction-processor/data-structures/NotificationItem.swift](../diction-processor/data-structures/NotificationItem.swift) | 16 | 0 |
| [diction-processor/data-structures/Paragraph.swift](../diction-processor/data-structures/Paragraph.swift) | 95 | 0 |
| [diction-processor/data-structures/PitchDatum.swift](../diction-processor/data-structures/PitchDatum.swift) | 54 | 0 |
| [diction-processor/data-structures/PunctuationMap.swift](../diction-processor/data-structures/PunctuationMap.swift) | 25 | 0 |
| [diction-processor/data-structures/Queue.swift](../diction-processor/data-structures/Queue.swift) | 47 | 0 |
| [diction-processor/data-structures/Sentence.swift](../diction-processor/data-structures/Sentence.swift) | 95 | 0 |
| [diction-processor/data-structures/SoundIntensityDatum.swift](../diction-processor/data-structures/SoundIntensityDatum.swift) | 44 | 0 |
| [diction-processor/data-structures/Speaker.swift](../diction-processor/data-structures/Speaker.swift) | 116 | 0 |
| [diction-processor/data-structures/SynthesizerItem.swift](../diction-processor/data-structures/SynthesizerItem.swift) | 18 | 0 |
| [diction-processor/data-structures/VoiceCommandDatum.swift](../diction-processor/data-structures/VoiceCommandDatum.swift) | 59 | 0 |
| [diction-processor/enums/AudioDeviceType.swift](../diction-processor/enums/AudioDeviceType.swift) | 29 | 0 |
| [diction-processor/enums/DirectionType.swift](../diction-processor/enums/DirectionType.swift) | 18 | 0 |
| [diction-processor/enums/EntryTrackType.swift](../diction-processor/enums/EntryTrackType.swift) | 15 | 0 |
| [diction-processor/enums/InvalidVoiceCommandType.swift](../diction-processor/enums/InvalidVoiceCommandType.swift) | 20 | 0 |
| [diction-processor/enums/NotificationType.swift](../diction-processor/enums/NotificationType.swift) | 16 | 0 |
| [diction-processor/enums/Notifications.swift](../diction-processor/enums/Notifications.swift) | 95 | 0 |
| [diction-processor/enums/RecognitionTask.swift](../diction-processor/enums/RecognitionTask.swift) | 14 | 0 |
| [diction-processor/enums/ScaleUnitType.swift](../diction-processor/enums/ScaleUnitType.swift) | 16 | 0 |
| [diction-processor/enums/SegmentPosition.swift](../diction-processor/enums/SegmentPosition.swift) | 15 | 0 |
| [diction-processor/enums/SelectionChangeType.swift](../diction-processor/enums/SelectionChangeType.swift) | 14 | 0 |
| [diction-processor/enums/SelectionDirection.swift](../diction-processor/enums/SelectionDirection.swift) | 15 | 0 |
| [diction-processor/enums/SentencePosition.swift](../diction-processor/enums/SentencePosition.swift) | 15 | 0 |
| [diction-processor/enums/TimeNormalizerType.swift](../diction-processor/enums/TimeNormalizerType.swift) | 14 | 0 |
| [diction-processor/enums/TransformationType.swift](../diction-processor/enums/TransformationType.swift) | 22 | 0 |
| [diction-processor/enums/VocalRegister.swift](../diction-processor/enums/VocalRegister.swift) | 14 | 0 |
| [diction-processor/extensions/AVAudioSession+Headphones.swift](../diction-processor/extensions/AVAudioSession+Headphones.swift) | 55 | 0 |
| [diction-processor/extensions/AVPlayer+Playback.swift](../diction-processor/extensions/AVPlayer+Playback.swift) | 21 | 0 |
| [diction-processor/extensions/CMTimeMapping+subscript.swift](../diction-processor/extensions/CMTimeMapping+subscript.swift) | 22 | 0 |
| [diction-processor/extensions/CenteredButton.swift](../diction-processor/extensions/CenteredButton.swift) | 60 | 0 |
| [diction-processor/extensions/Collection+distance.swift](../diction-processor/extensions/Collection+distance.swift) | 13 | 0 |
| [diction-processor/extensions/Date+Subtract.swift](../diction-processor/extensions/Date+Subtract.swift) | 15 | 0 |
| [diction-processor/extensions/Dictionary+isEqual.swift](../diction-processor/extensions/Dictionary+isEqual.swift) | 29 | 0 |
| [diction-processor/extensions/Double+Rounded.swift](../diction-processor/extensions/Double+Rounded.swift) | 17 | 0 |
| [diction-processor/extensions/Float+Rounded.swift](../diction-processor/extensions/Float+Rounded.swift) | 17 | 0 |
| [diction-processor/extensions/MPVolumeView+volumeSlider.swift](../diction-processor/extensions/MPVolumeView+volumeSlider.swift) | 22 | 0 |
| [diction-processor/extensions/NSRange+Range.swift](../diction-processor/extensions/NSRange+Range.swift) | 30 | 0 |
| [diction-processor/extensions/NSRange+toTextRange.swift](../diction-processor/extensions/NSRange+toTextRange.swift) | 20 | 0 |
| [diction-processor/extensions/Sequence+containsAnyOf.swift](../diction-processor/extensions/Sequence+containsAnyOf.swift) | 15 | 0 |
| [diction-processor/extensions/String+Substring+Replace+TrimTrailingPunctuation.swift](../diction-processor/extensions/String+Substring+Replace+TrimTrailingPunctuation.swift) | 51 | 0 |
| [diction-processor/extensions/StringIndex+distance.swift](../diction-processor/extensions/StringIndex+distance.swift) | 13 | 0 |
| [diction-processor/extensions/StringProtocol+distance.swift](../diction-processor/extensions/StringProtocol+distance.swift) | 14 | 0 |
| [diction-processor/extensions/TimeConstant+Minute+Hour.swift](../diction-processor/extensions/TimeConstant+Minute+Hour.swift) | 14 | 0 |
| [diction-processor/extensions/UIColor+hex.swift](../diction-processor/extensions/UIColor+hex.swift) | 39 | 0 |
| [diction-processor/extensions/UITextView+NoActions.swift](../diction-processor/extensions/UITextView+NoActions.swift) | 18 | 0 |
| [diction-processor/extensions/UITextView+VisibleRange.swift](../diction-processor/extensions/UITextView+VisibleRange.swift) | 22 | 0 |
| [diction-processor/extensions/UIView+Border.swift](../diction-processor/extensions/UIView+Border.swift) | 49 | 0 |
| [diction-processor/pitchy/AcousticWave.swift](../diction-processor/pitchy/AcousticWave.swift) | 42 | 0 |
| [diction-processor/pitchy/Error.swift](../diction-processor/pitchy/Error.swift) | 7 | 0 |
| [diction-processor/pitchy/FrequencyValidator.swift](../diction-processor/pitchy/FrequencyValidator.swift) | 16 | 0 |
| [diction-processor/pitchy/Note.swift](../diction-processor/pitchy/Note.swift) | 83 | 0 |
| [diction-processor/pitchy/NoteCalculator.swift](../diction-processor/pitchy/NoteCalculator.swift) | 128 | 0 |
| [diction-processor/pitchy/Pitch.swift](../diction-processor/pitchy/Pitch.swift) | 51 | 0 |
| [diction-processor/pitchy/PitchCalculator.swift](../diction-processor/pitchy/PitchCalculator.swift) | 38 | 0 |
| [diction-processor/pitchy/WaveCalculator.swift](../diction-processor/pitchy/WaveCalculator.swift) | 68 | 0 |
| [diction-processor/protocols/DetailDelegate.swift](../diction-processor/protocols/DetailDelegate.swift) | 14 | 0 |
| [diction-processor/protocols/SegueProtocol.swift](../diction-processor/protocols/SegueProtocol.swift) | 32 | 0 |
| [diction-processorTests/diction_processorTests.swift](../diction-processorTests/diction_processorTests.swift) | 137 | 0 |
| [diction-processorUITests/diction_processorUITests.swift](../diction-processorUITests/diction_processorUITests.swift) | 43 | 0 |
| [native/Package.swift](../native/Package.swift) | 3 | 0 |
| [native/Sources/RecognitionLifecycle/RecognitionLifecycle.swift](../native/Sources/RecognitionLifecycle/RecognitionLifecycle.swift) | 31 | 0 |
| [native/Tests/RecognitionLifecycleTests/RecognitionLifecycleTests.swift](../native/Tests/RecognitionLifecycleTests/RecognitionLifecycleTests.swift) | 40 | 0 |

## Remaining gaps
