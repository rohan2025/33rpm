#!/bin/zsh
# Anonymous numbers: DMG downloads per release (GitHub counts these, no personal data) and GitHub repo traffic.
# Extension installs are in the Chrome Web Store dashboard; website visits in the site's analytics.
set -euo pipefail
REPO=rohan2025/33rpm

echo "App downloads (DMG)"
gh api "repos/$REPO/releases" --paginate -q '.[] | .tag_name as $t
  | ([.assets[] | select(.name | endswith(".dmg")) | .download_count] | add // 0) as $n
  | "  \($t)\t\($n)"'
gh api "repos/$REPO/releases" --paginate -q '[.[].assets[] | select(.name | endswith(".dmg")) | .download_count] | add // 0' \
  | awk '{ s += $1 } END { print "  total\t" s }'

echo
echo "GitHub repo, last 14 days"
gh api "repos/$REPO/traffic/views" -q '"  page views\t\(.count) (\(.uniques) people)"'
gh api "repos/$REPO/traffic/popular/referrers" -q '.[] | "  from \(.referrer)\t\(.count) (\(.uniques) people)"'
