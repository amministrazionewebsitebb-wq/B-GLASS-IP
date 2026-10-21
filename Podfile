# VLC is an optional second video engine (MKV, AVI, raw MPEG-TS). scripts/build_ipa.sh runs `pod install` only when asked for it.
platform :ios, '16.0'
use_frameworks!
project 'BGlass.xcodeproj'

target 'BGlass' do
  pod 'MobileVLCKit', '~> 3.6'
end

post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |c|
      c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
    end
  end
end
