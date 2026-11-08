# Dépendances CocoaPods. Ordre : `xcodegen generate` puis `pod install`,
# puis ouvrir Zapp.xcworkspace (et non plus Zapp.xcodeproj).
platform :ios, '17.0'
project 'Zapp.xcodeproj'
inhibit_all_warnings!

target 'Zapp' do
  # Moteur VLC officiel : TS, MKV, AVI, FLV, RTMP, RTSP, UDP, MMS…
  pod 'MobileVLCKit', '~> 3.6'

  target 'ZappTests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    end
  end
end
