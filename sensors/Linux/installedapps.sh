#!/bin/sh
#
# Luminum "Installed Applications" Sensor (Linux)
# ===============================================

bin_re='^/?(usr/)?s?bin/[^/]+$'

{
  if [ -f /etc/slackware-version ]; then
    pkgdb=/var/lib/pkgtools/packages
    [ -d "$pkgdb" ] || pkgdb=/var/log/packages

    awk -v re="$bin_re" '
      FNR == 1 {
        n = split(FILENAME, a, "/"); m = split(a[n], b, "-")
        name = b[1]; for (i = 2; i <= m - 3; i++) name = name "-" b[i]
        ver = b[m - 2]
      }
      $0 ~ re { print name "|" ver; nextfile }
    ' "$pkgdb"/*

  elif command -v dpkg-query >/dev/null 2>&1; then
    dpkg-query -W -f='${binary:Package}|${Version}\n' $(
      grep -lE "${bin_re}" /var/lib/dpkg/info/*.list |
        sed -E 's#.*/##; s#\.list$##')

  elif command -v rpm >/dev/null 2>&1; then
    rpm -qa --qf '[%{=NAME}|%{=VERSION}-%{=RELEASE}|%{FILENAMES}\n]' |
      awk -F'|' -v re="$bin_re" '$3 ~ re { print $1 "|" $2 }'
  fi

  if command -v flatpak >/dev/null 2>&1; then
    flatpak list --app --columns=application,version 2>/dev/null |
      awk '{ print $1 "|" $2 }'
  fi

  if command -v snap >/dev/null 2>&1; then
    snap list 2>/dev/null | awk 'NR > 1 { print $1 "|" $2 }'
  fi
} | sort -fu