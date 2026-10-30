import Cocoa
import FlutterMacOS
import CoreServices

/// Surveille un dossier choisi par l'utilisateur sur macOS (FSEvents) et
/// liste son contenu. Porté du prototype Xplor (`DirectorySurveillance.swift`,
/// Ben NDUI, 26/01/2024) : même moteur FSEventStream, mais le choix du
/// dossier passe désormais par un vrai `NSOpenPanel` — le prototype
/// d'origine faisait taper le chemin à la main dans un champ texte.
///
/// ⚠️ App sandboxée (`com.apple.security.app-sandbox`) : un chemin brut ne
/// suffit PAS. L'accès à un dossier choisi via `NSOpenPanel` n'est accordé
/// que pour la session en cours ; sans security-scoped bookmark, lister ou
/// surveiller ce même dossier au lancement SUIVANT échoue silencieusement
/// (`Operation not permitted`). `pickDirectory` renvoie donc le bookmark en
/// plus du chemin, et toute opération ultérieure le reçoit en entrée.
public class SmoothandesignFolderWatcherPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var stream: FSEventStreamRef?
  private var watchedUrl: URL?

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
            let bookmark = args["bookmark"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "bookmark manquant", details: nil))
        return
      }
      listFiles(bookmarkData: bookmark.data, result: result)
    case "startWatching":
      guard let args = call.arguments as? [String: Any],
            let bookmark = args["bookmark"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "bookmark manquant", details: nil))
        return
      }
      startWatching(bookmarkData: bookmark.data, result: result)
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
      guard response == .OK, let url = panel.url else {
        result(nil)
        return
      }
      do {
        let bookmark = try url.bookmarkData(
          options: .withSecurityScope,
          includingResourceValuesForKeys: nil,
          relativeTo: nil)
        result(["path": url.path, "bookmark": FlutterStandardTypedData(bytes: bookmark)])
      } catch {
        result(FlutterError(code: "BOOKMARK_FAILED", message: error.localizedDescription, details: nil))
      }
    }
  }

  /// Résout un bookmark et commence l'accès security-scoped. L'appelant
  /// DOIT appeler `url.stopAccessingSecurityScopedResource()` une fois
  /// l'opération terminée (voir [listFiles] pour l'usage ponctuel, et
  /// [stopWatching] pour l'accès maintenu ouvert pendant la surveillance).
  private func resolveAndStartAccess(_ bookmarkData: Data) -> URL? {
    var isStale = false
    guard let url = try? URL(
      resolvingBookmarkData: bookmarkData,
      options: .withSecurityScope,
      relativeTo: nil,
      bookmarkDataIsStale: &isStale),
      url.startAccessingSecurityScopedResource()
    else {
      return nil
    }
    return url
  }

  // MARK: - Liste du contenu

  private func listFiles(bookmarkData: Data, result: @escaping FlutterResult) {
    guard let url = resolveAndStartAccess(bookmarkData) else {
      result(FlutterError(code: "ACCESS_DENIED", message: "Accès au dossier refusé", details: nil))
      return
    }
    defer { url.stopAccessingSecurityScopedResource() }

    let fileManager = FileManager.default
    do {
      let names = try fileManager.contentsOfDirectory(atPath: url.path)
      let files: [[String: Any]] = names.compactMap { name in
        let fullPath = (url.path as NSString).appendingPathComponent(name)
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

  private func startWatching(bookmarkData: Data, result: @escaping FlutterResult) {
    stopWatching()

    guard let url = resolveAndStartAccess(bookmarkData) else {
      result(FlutterError(code: "ACCESS_DENIED", message: "Accès au dossier refusé", details: nil))
      return
    }
    // Gardé ouvert tant que la surveillance tourne — fermé dans stopWatching().
    watchedUrl = url

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
      [url.path] as CFArray,
      FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
      1.0,
      FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents))

    guard let stream = stream else {
      result(FlutterError(code: "WATCH_FAILED", message: "FSEventStreamCreate a échoué", details: nil))
      return
    }
    FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
    FSEventStreamStart(stream)
    result(nil)
  }

  private func stopWatching() {
    if let stream = stream {
      FSEventStreamStop(stream)
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
      self.stream = nil
    }
    watchedUrl?.stopAccessingSecurityScopedResource()
    watchedUrl = nil
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
