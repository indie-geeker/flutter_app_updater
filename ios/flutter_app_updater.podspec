Pod::Spec.new do |s|
  s.name             = 'flutter_app_updater'
  s.version          = '3.0.0'
  s.summary          = 'UI-free update actions for commercial Flutter apps.'
  s.description      = <<-DESC
Manifest-driven release selection and explicit App Store update actions for Flutter applications.
                       DESC
  s.homepage         = 'https://github.com/indie-geeker/flutter_app_updater'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Indie Geeker' => 'indiegeeker@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'
end
