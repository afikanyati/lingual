import AVFoundation

public enum InputSignalTrackerError: Error {
  case inputNodeMissing
}

final class InputSignalTracker: SignalTracker {
  weak var delegate: SignalTrackerDelegate?
  var levelThreshold: Float?

  private let bufferSize: AVAudioFrameCount
  private var audioChannel: AVCaptureAudioChannel?
  private let captureSession = AVCaptureSession()
  private var audioEngine: AVAudioEngine?
  private let session = AVAudioSession.sharedInstance()
  private let bus = 0

//  var peakLevel: Float? {
//    return audioChannel?.peakHoldLevel
//  }
//
//  var averageLevel: Float? {
//    return audioChannel?.averagePowerLevel
//  }

  var mode: SignalTrackerMode {
    return .record
  }

  // MARK: - Initialization

  required init(bufferSize: AVAudioFrameCount = 1024,
                delegate: SignalTrackerDelegate? = nil) {
    self.bufferSize = bufferSize
    self.delegate = delegate
  }

  // MARK: - Tracking

  func start() throws {
    do {
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker, .duckOthers])
    } catch let error as NSError {
        print("===== There was an error requesting permissions to record audio or setting session category: \(error.localizedDescription) =====")
    } catch {
        print("===== There was an error requesting permissions to record audio or setting session category =====")
    }
    
    audioEngine = AVAudioEngine()

    let node = audioEngine!.inputNode

    let format = node.outputFormat(forBus: bus)

    node.installTap(onBus: bus, bufferSize: bufferSize, format: format) { buffer, time in
        guard let averageLevel = self.computeAvgLevel(buffer: buffer) else { return }

      let levelThreshold = self.levelThreshold ?? -1000000.0

      if averageLevel > levelThreshold {
        DispatchQueue.main.async {
          self.delegate?.signalTracker(self, didReceiveBuffer: buffer, atTime: time)
        }
      } else {
        DispatchQueue.main.async {
          self.delegate?.signalTrackerWentBelowLevelThreshold(self)
        }
      }
    }

    audioEngine?.prepare()
    try audioEngine?.start()
    try session.setActive(true)
//    captureSession.startRunning()
//    guard captureSession.isRunning == true else {
//        throw InputSignalTrackerError.inputNodeMissing
//    }
  }

  func stop() {
    guard audioEngine != nil else {
      return
    }

    audioEngine?.stop()
    audioEngine?.reset()
    audioEngine = nil
//    captureSession.stopRunning()
    }
    
    func computeAvgLevel(buffer: AVAudioPCMBuffer) -> Float? {
        // gives you an array of pointers to each sample’s data
        guard let channelData = buffer.floatChannelData else { return nil }

        let channelDataValue = channelData.pointee
        
        // Converting from an array of UnsafeMutablePointer<Float> to an array of Float makes later calculations easier.
        let channelDataValueArray = stride(from: 0,
                                           to: Int(buffer.frameLength),
                                           by: buffer.stride).map{ channelDataValue[$0] }
        // Compute average power using root mean square
        let rmsNumerator = channelDataValueArray.map{ $0 * $0 }.reduce(0, +)
        let rms = sqrt(rmsNumerator / Float(buffer.frameLength))
        
        // Convert the RMS to decibels
        // This should be a value between -160 and 0, but if rms is negative, this value would be NaN.
        let avgPower = 20 * log10(rms)
        
        return avgPower
    }
}
