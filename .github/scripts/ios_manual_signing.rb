# Release CI only (release-ios.yml): switches the Runner target's Release
# configuration from Automatic to Manual signing with the App Store profile
# installed by the workflow. The change lives only in the runner's checkout —
# the committed project keeps Automatic signing for local development.
#
# usage: ruby ios_manual_signing.rb <Runner.xcodeproj> <team id> <profile name>
require 'xcodeproj'

project_path, team_id, profile_name = ARGV
abort 'usage: ios_manual_signing.rb <Runner.xcodeproj> <team id> <profile name>' if profile_name.to_s.empty?

project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'Runner' } or abort 'Runner target not found'
config = target.build_configurations.find { |c| c.name == 'Release' } or abort 'Release configuration not found'

settings = config.build_settings
settings['CODE_SIGN_STYLE'] = 'Manual'
settings['DEVELOPMENT_TEAM'] = team_id
settings['CODE_SIGN_IDENTITY'] = 'Apple Distribution'
settings['CODE_SIGN_IDENTITY[sdk=iphoneos*]'] = 'Apple Distribution'
settings['PROVISIONING_PROFILE_SPECIFIER'] = profile_name
project.save

puts "Runner/Release: manual signing, team #{team_id}, profile \"#{profile_name}\""
