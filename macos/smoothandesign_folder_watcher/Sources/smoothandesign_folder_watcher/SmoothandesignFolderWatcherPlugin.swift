import Cocoa
import FlutterMacOS
import CoreServices

/// Surveille un dossier choisi par l'utilisateur sur macOS (FSEvents) et
/// liste son contenu. Porté du prototype Xplor (`DirectorySurveillance.swift`,
/// Ben NDUI, 26/01/2024) : même moteur FSEventStream, mais le choix du
/// dossier passe désormais par un vrai `NSOpenPanel` — le prototype
/// d'origine faisait taper le chemin à la main dans un champ texte.
public class SmoothandesignFolderWatcherPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var stream: FSEventStreamRef?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(
      name: "smoothandesign_folder_watcher/methods",
      binaryMessenger: registrar.messenger)
    let eventChannel = FlutterEventChannel(
      name: "smoothandesign_folder_watcher/events",
      binaryMessenger: registrar.messenger)

    let instance = SmoothandesignFolderWatcherPlugin()
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pickDirectory":
      pickDirectory(result: result)
    case "listFiles":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "path manquant", details: nil))
        return
      }
      listFiles(path: path, result: result)
    case "startWatching":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "path manquant", details: nil))
        return
      }
      startWatching(path: path)
      result(nil)
    case "stopWatching":
      stopWatching()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Sélection du dossier

  private func pickDirectory(result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = NSLocalizedString("Choisir", comment: "")

    panel.begin { response in
      if response == .OK, let url = panel.url {
        result(url.path)
      } else {
        result(nil)
      }
    }
  }

  // MARK: - Liste du contenu

  private func listFiles(path: String, result: @escaping FlutterResult) {
    let fileManager = FileManager.default
    do {
      let names = try fileManager.contentsOfDirectory(atPath: path)
      let files: [[String: Any]] = names.compactMap { name in
        let fullPath = (path as NSString).appendingPathComponent(name)
        guard let attrs = try? fileManager.attributesOfItem(atPath: fullPath) else { return nil }
        let modifiedAt = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = attrs[.size] as? Int ?? 0
        return [
          "name": name,
          "path": fullPath,
          "modifiedAtEpochSeconds": modifiedAt,
          "sizeBytes": size,
        ]
      }
      result(files)
    } catch {
      result(FlutterError(code: "LIST_FAILED", message: error.localizedDescription, details: nil))
    }
  }

  // MARK: - Surveillance (FSEvents)

  private func startWatching(path: String) {
    stopWatching()

    var context = FSEventStreamContext(
      version: 0,
      info: Unmanaged.passUnretained(self).toOpaque(),
      retain: nil,
      release: nil,
      copyDescription: nil)

    let callback: FSEventStreamCallback = { (_, clientCallBackInfo, numEvents, eventPaths, eventFlags, _) in
      guard let info = clientCallBackInfo else { return }
      let plugin = Unmanaged<SmoothandesignFolderWatcherPlugin>.fromOpaque(info).takeUnretainedValue()
      guard let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] else { return }
      for i in 0..<numEvents {
        plugin.notifyChange(path: paths[i], flag: eventFlags[i])
      }
    }

    stream = FSEventStreamCreate(
      kCFAllocatorDefault,
      callback,
      &context,
      [path] as CFArray,
      FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
      1.0,
      FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents))

    guard let stream = stream else { return }
    FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
    FSEventStreamStart(stream)
  }

  private func stopWatching() {
    guard let stream = stream else { return }
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream)
    FSEventStreamRelease(stream)
    self.stream = nil
  }

  private func notifyChange(path: String, flag: FSEventStreamEventFlags) {
    eventSink?(["path": path, "type": changeType(for: flag)])
  }

  /// Traduit les flags FSEvents en un type lisible — le Dart ne doit pas
  /// connaître l'encodage bas niveau d'Apple.
  private func changeType(for flag: FSEventStreamEventFlags) -> String {
    if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0 {
      return "removed"
    }
    if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0 {
      return "created"
    }
    if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0 {
      return "renamed"
    }
    if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified) != 0 {
      return "modified"
    }
    return "unknown"
  }

  // MARK: - FlutterStreamHandler

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    stopWatching()
    return nil
  }
}
