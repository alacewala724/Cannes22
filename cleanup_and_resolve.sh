#!/bin/bash

echo "🧹 Cleaning up Xcode and Simulator data..."

# Shutdown all simulators
echo "📱 Shutting down simulators..."
xcrun simctl shutdown all

# Erase all simulator data
echo "🗑️ Erasing simulator data..."
xcrun simctl erase all

# Delete unavailable simulators
echo "🗑️ Removing unavailable simulators..."
xcrun simctl delete unavailable

# Clear derived data
echo "🗑️ Clearing derived data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/*

# Clear Xcode caches
echo "🗑️ Clearing Xcode caches..."
rm -rf ~/Library/Caches/com.apple.dt.Xcode

# Clear Swift Package Manager cache
echo "🗑️ Clearing Swift Package Manager cache..."
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf ~/Library/Developer/Xcode/DerivedData/*/SourcePackages

# Clear old archives (keep last 3)
echo "🗑️ Cleaning old archives..."
cd ~/Library/Developer/Xcode/Archives
ls -t | tail -n +4 | xargs rm -rf

echo "✅ Cleanup complete!"
echo "💾 Available space:"
df -h | grep "/System/Volumes/Data"
echo ""

# Automatically resolve packages
echo "📦 Resolving Swift Package Manager dependencies..."
cd /Users/aamirlacewala/Downloads/Cannes22-main
xcodebuild -project Cannes.xcodeproj -resolvePackageDependencies

echo "✅ All done! Your project is ready to build."
