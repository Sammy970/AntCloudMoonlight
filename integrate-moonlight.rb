# Integrates the AntCloud panel into a Moonlight iOS checkout.
#
# Layout expected (see README): moonlight-ios/ cloned next to this repo, e.g.
#   antcloud-moonlight/        <- this repo
#   moonlight-ios/             <- git clone of moonlight-stream/moonlight-ios (submodules fetched)
#
# This script is idempotent. It:
#   1. applies moonlight-objc.patch (edits to MainFrameViewController.m, AppDelegate.m, Info.plist)
#   2. adds the AntCloud Swift files (panel + Shared) and the SocketIO package to the Moonlight target
#   3. installs the AntCloud app icon
#
# Usage: ruby integrate-moonlight.rb [path-to-moonlight-ios]
require 'xcodeproj'

here = __dir__
moonlight = File.expand_path(ARGV[0] || File.join(here, '..', 'moonlight-ios'))
abort "moonlight-ios not found at #{moonlight}" unless File.directory?(moonlight)
project_path = File.join(moonlight, 'Moonlight.xcodeproj')

# 1. Apply the Objective-C / plist patch (skip if already applied).
patch = File.join(here, 'moonlight-objc.patch')
if system("git -C #{moonlight} apply --reverse --check #{patch} > /dev/null 2>&1")
  puts '• ObjC patch already applied'
else
  system("git -C #{moonlight} apply #{patch}") or abort 'failed to apply moonlight-objc.patch'
  puts '• applied ObjC patch'
end

project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'Moonlight' } or abort 'Moonlight target not found'

# 2. Add Swift sources: the panel files here, plus the Shared code (minus RootView — the panel
#    supplies its own root). Files are referenced in place from this repo.
shared = %w[
  Config.swift Log.swift API/APIClient.swift Auth/AuthStore.swift Auth/Keychain.swift
  Session/SessionService.swift Session/StreamSettings.swift
  Views/LoginView.swift Views/PlatformStyles.swift
].map { |f| File.join(here, 'Shared', f) }
panel = Dir[File.join(here, '*.swift')].sort
(shared + panel).each { |f| abort "missing #{f}" unless File.exist?(f) }

group = project.main_group['AntCloud'] || project.main_group.new_group('AntCloud')
existing = target.source_build_phase.files_references.map(&:real_path).map(&:to_s)
(panel + shared).each do |path|
  next if existing.include?(path)
  ref = group.files.find { |f| f.real_path.to_s == path } || group.new_reference(path)
  target.add_file_references([ref])
end
bridging = File.join(here, 'AntCloud-Bridging-Header.h')
unless group.files.any? { |f| f.real_path.to_s == bridging }
  group.new_reference(bridging)
end

# SocketIO package.
url = 'https://github.com/socketio/socket.io-client-swift'
package = project.root_object.package_references.find { |p| p.repositoryURL == url }
unless package
  package = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  package.repositoryURL = url
  package.requirement = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => '16.1.1' }
  project.root_object.package_references << package
end
unless target.package_product_dependencies.any? { |d| d.product_name == 'SocketIO' }
  dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dependency.package = package
  dependency.product_name = 'SocketIO'
  target.package_product_dependencies << dependency
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dependency
  target.frameworks_build_phase.files << build_file
end

target.build_configurations.each do |config|
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = bridging
end

project.save

# 3. App icon: rasterize AppIcon-1024.png into the appiconset sizes.
iconset = File.join(moonlight, 'Limelight', 'Images.xcassets', 'AppIcon.appiconset')
src = File.join(here, 'AppIcon-1024.png')
if File.exist?(src) && File.directory?(iconset)
  {
    'Icon-App-29x29@1x.png' => 29, 'Icon-App-29x29@2x.png' => 58, 'Icon-App-29x29@2x-1.png' => 58,
    'Icon-App-29x29@3x.png' => 87, 'Icon-App-40x40@1x.png' => 40, 'Icon-App-40x40@2x.png' => 80,
    'Icon-App-40x40@2x-1.png' => 80, 'Icon-App-40x40@3x.png' => 120, 'Icon-App-60x60@2x.png' => 120,
    'Icon-App-60x60@3x.png' => 180, 'Icon-App-76x76@1x.png' => 76, 'Icon-App-76x76@2x.png' => 152,
    'Icon-App-83.5x83.5@2x.png' => 167
  }.each do |name, size|
    system('sips', '-z', size.to_s, size.to_s, src, '--out', File.join(iconset, name), out: File::NULL, err: File::NULL)
  end
  FileUtils.cp(src, File.join(iconset, '1024x icon.png')) if defined?(FileUtils) || require('fileutils')
  puts '• installed app icon'
end

puts "Integrated AntCloud into #{target.name}: #{target.source_build_phase.files.count} source files"
