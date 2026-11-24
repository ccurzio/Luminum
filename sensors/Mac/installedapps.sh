#!/bin/bash
#
# Luminum "Installed Applications" Sensor (macOS)
# ===============================================

/usr/bin/mdfind -0 "kMDItemContentType == 'com.apple.application-bundle'" |
while IFS= read -r -d '' app; do
	case ${app%/*} in
		*.app | *.app/*) continue ;;
		*/group.is.workflow.my | */group.is.workflow.my/*) continue ;;
		*/storage/default) continue ;;
		*/Homebrew/Library/Homebrew/test/*) continue ;;
	esac

	plist="$app/Contents/Info.plist"
	ver=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null) ||
	ver=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null)

	name=${app##*/}
	name=${name%.app}
	[ "$name" = liquiddetectiond ] && continue
	printf '%s|%s\n' "$name" "$ver"
done | sort -fu
