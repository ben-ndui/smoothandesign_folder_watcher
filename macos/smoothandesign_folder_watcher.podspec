#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint smoothandesign_folder_watcher.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'smoothandesign_folder_watcher'
  s.version          = '0.0.1'
  s.summary          = 'Choisir et surveiller un dossier local sur macOS (FSEvents).'
  s.description      = <<-DESC
Sélection native d'un dossier (NSOpenPanel), liste de son contenu et
notifications en temps réel des fichiers créés/modifiés/supprimés/renommés
(FSEventStream). Smooth & Design.
                       DESC
  s.homepage         = 'https://github.com/ben-ndui/smoothandesign_folder_watcher'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Smooth & Design' => 'contact@smoothandesign.fr' }

  s.source           = { :path => '.' }
  s.source_files = 'smoothandesign_folder_watcher/Sources/smoothandesign_folder_watcher/**/*'
  s.frameworks       = 'CoreServices'

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'smoothandesign_folder_watcher_privacy' => ['smoothandesign_folder_watcher/Sources/smoothandesign_folder_watcher/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
