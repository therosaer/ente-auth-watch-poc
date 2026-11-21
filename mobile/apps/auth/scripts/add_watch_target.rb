# One-off script used to add the watchOS target to Runner.xcodeproj.
require "xcodeproj"

proj = Xcodeproj::Project.open("Runner.xcodeproj")
runner = proj.targets.find { |t| t.name == "Runner" }
abort "watch target already exists" if proj.targets.any? { |t| t.name == "EnteAuthWatch" }

watch = proj.new_target(:application, "EnteAuthWatch", :watchos, "9.0", nil, :swift, "Auth")

# Match the Runner's configuration names.
runner.build_configurations.map(&:name).each do |name|
  next if watch.build_configurations.any? { |c| c.name == name }
  base = watch.build_configurations.find { |c| c.name == "Release" }
  cfg = proj.new(Xcodeproj::Project::Object::XCBuildConfiguration)
  cfg.name = name
  cfg.build_settings = base.build_settings.dup
  watch.build_configuration_list.build_configurations << cfg
end

watch.build_configurations.each do |c|
  c.build_settings.merge!(
    "PRODUCT_BUNDLE_IDENTIFIER" => "io.ente.auth.watchkitapp",
    "PRODUCT_NAME" => "Auth",
    "GENERATE_INFOPLIST_FILE" => "YES",
    "INFOPLIST_KEY_CFBundleDisplayName" => "Auth",
    "INFOPLIST_KEY_WKApplication" => "YES",
    "INFOPLIST_KEY_WKCompanionAppBundleIdentifier" => "io.ente.auth",
    "SDKROOT" => "watchos",
    "SUPPORTED_PLATFORMS" => "watchos watchsimulator",
    "TARGETED_DEVICE_FAMILY" => "4",
    "WATCHOS_DEPLOYMENT_TARGET" => "9.0",
    "SWIFT_VERSION" => "5.0",
    "MARKETING_VERSION" => "1.0",
    "CURRENT_PROJECT_VERSION" => "1",
    "SKIP_INSTALL" => "YES",
    "ASSETCATALOG_COMPILER_APPICON_NAME" => "",
    "ENABLE_PREVIEWS" => "YES",
    "CODE_SIGN_STYLE" => "Automatic",
    "LD_RUNPATH_SEARCH_PATHS" => ["$(inherited)", "@executable_path/Frameworks"],
  )
  c.build_settings.delete("IPHONEOS_DEPLOYMENT_TARGET")
end

group = proj.main_group.new_group("WatchApp", "WatchApp")
Dir["WatchApp/*.swift"].sort.each do |f|
  ref = group.new_file(File.basename(f))
  watch.source_build_phase.add_file_reference(ref)
end

# Embed the watch app in the iOS app, ahead of Flutter's Thin Binary script.
phase = proj.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
phase.name = "Embed Watch Content"
phase.dst_subfolder_spec = "16"
phase.dst_path = "$(CONTENTS_FOLDER_PATH)/Watch"
bf = phase.add_file_reference(watch.product_reference, true)
bf.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }
idx = runner.build_phases.index { |b| b.respond_to?(:name) && b.name == "Embed Frameworks" }
runner.build_phases.insert(idx + 1, phase)
runner.add_dependency(watch)

proj.save
puts "ok"
