#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint smoothandesign_folder_watcher.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'smoothandesign_folder_watcher'
  s.version          = '0.0.1'
  s.summary          = 'Choisir et lister un dossier local (iOS/Android/macOS).'
  s.description      = <<-DESC
Sélection native d'un dossier (UIDocumentPickerViewController sur iOS,
NSOpenPanel sur macOS) et liste de son contenu. Smooth & Design.
                       DESC
  s.homepage         = 'https://github.com/ben-ndui/smoothandesign_folder_watcher'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Smooth & Design' => 'contact@smoothandesign.fr' }
  s.source           = { :path => '.' }
  s.source_files = 'smoothandesign_folder_watcher/Sources/smoothandesign_folder_watcher/**/*'
  s.dependency 'Flutter'
  # UIDocumentPickerViewController(forOpeningContentTypes:) et UTType.folder
  # exigent iOS 14+ (uzme cible deja iOS 15.5).
  s.platform = :ios, '14.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'smoothandesign_folder_watcher_privacy' => ['smoothandesign_folder_watcher/Sources/smoothandesign_folder_watcher/PrivacyInfo.xcprivacy']}
end
