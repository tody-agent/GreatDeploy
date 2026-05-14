.PHONY: test test-gate build-release package-ad-hoc

test:
	xcodegen
	xcodebuild test -project GreatDeploy.xcodeproj -scheme GreatDeploy -destination 'platform=macOS'

test-gate:
	@echo "Running Test Gate for GreatDeploy..."
	xcodegen
	xcodebuild test -project GreatDeploy.xcodeproj -scheme GreatDeploy -destination 'platform=macOS' | xcpretty || xcodebuild test -project GreatDeploy.xcodeproj -scheme GreatDeploy -destination 'platform=macOS'

build-release:
	@echo "Building Release version for GreatDeploy..."
	xcodegen
	xcodebuild -project GreatDeploy.xcodeproj -scheme GreatDeploy -configuration Release clean build CONFIGURATION_BUILD_DIR="$(PWD)/build/Release"
	@echo "Zipping the app for deployment..."
	cd build/Release && zip -ry ../GreatDeploy-macOS-Release.zip GreatDeploy.app
	@echo "Deployment package created at build/GreatDeploy-macOS-Release.zip"

package-ad-hoc:
	./script/package_ad_hoc.sh
