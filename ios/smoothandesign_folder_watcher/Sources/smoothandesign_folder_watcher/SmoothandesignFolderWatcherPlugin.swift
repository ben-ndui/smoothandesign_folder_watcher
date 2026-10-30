import Flutter
import UIKit
import UniformTypeIdentifiers

/// Choisir un dossier (app Fichiers) et lister son contenu sur iOS.
///
/// Pas d'équivalent FSEvents public sur iOS pour un dossier arbitraire —
/// contrairement à macOS, ce plugin n'implémente PAS de surveillance native
/// ici. Le polling (relister périodiquement) est géré côté Dart, uniforme
/// avec Android. Voir smoothandesign_folder_watcher.dart.
public class SmoothandesignFolderWatcherPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
  private var pickerResult: FlutterResult?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "smoothandesign_folder_watcher/methods",
      binaryMessenger: registrar.messenger())
    let instance = SmoothandesignFolderWatcherPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
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
    case "copyToLocalFile":
      guard let args = call.arguments as? [String: Any],
            let bookmark = args["bookmark"] as? FlutterStandardTypedData,
            let fileUri = args["fileUri"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "arguments manquants", details: nil))
        return
      }
      copyToLocalFile(bookmarkData: bookmark.data, filePath: fileUri, result: result)
    case "startWatching", "stopWatching":
      // Pas de surveillance native sur iOS (voir doc de classe) : le Dart
      // bascule sur du polling. On accepte l'appel pour que l'API reste
      // identique à macOS côté consommateur.
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Sélection du dossier

  private func pickDirectory(result: @escaping FlutterResult) {
    guard let rootViewController = UIApplication.shared.connectedScenes
      .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
      .first?.rootViewController else {
      result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "Impossible de présenter le sélecteur", details: nil))
      return
    }

    pickerResult = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
    picker.delegate = self
    rootViewController.present(picker, animated: true)
  }

  public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else {
      pickerResult?(nil)
      pickerResult = nil
      return
    }

    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }

    do {
      let bookmark = try url.bookmarkData()
      pickerResult?(["path": url.path, "bookmark": FlutterStandardTypedData(bytes: bookmark)])
    } catch {
      pickerResult?(FlutterError(code: "BOOKMARK_FAILED", message: error.localizedDescription, details: nil))
    }
    pickerResult = nil
  }

  public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pickerResult?(nil)
    pickerResult = nil
  }

  // MARK: - Liste du contenu

  private func listFiles(bookmarkData: Data, result: @escaping FlutterResult) {
    var isStale = false
    guard let url = try? URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale),
          url.startAccessingSecurityScopedResource() else {
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

  // MARK: - Copie locale avant envoi

  /// L'accès security-scoped n'est ouvert que le temps de [listFiles] — pour
  /// lire un fichier plus tard (envoi à un artiste), il faut rouvrir l'accès
  /// puis copier le fichier dans le cache de l'app, dont la lecture ne
  /// dépend plus du bookmark.
  private func copyToLocalFile(bookmarkData: Data, filePath: String, result: @escaping FlutterResult) {
    var isStale = false
    guard let folderUrl = try? URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale),
          folderUrl.startAccessingSecurityScopedResource() else {
      result(FlutterError(code: "ACCESS_DENIED", message: "Accès au dossier refusé", details: nil))
      return
    }
    defer { folderUrl.stopAccessingSecurityScopedResource() }

    let sourceUrl = URL(fileURLWithPath: filePath)
    let destUrl = FileManager.default.temporaryDirectory.appendingPathComponent(sourceUrl.lastPathComponent)

    do {
      if FileManager.default.fileExists(atPath: destUrl.path) {
        try FileManager.default.removeItem(at: destUrl)
      }
      try FileManager.default.copyItem(at: sourceUrl, to: destUrl)
      result(destUrl.path)
    } catch {
      result(FlutterError(code: "COPY_FAILED", message: error.localizedDescription, details: nil))
    }
  }
}
