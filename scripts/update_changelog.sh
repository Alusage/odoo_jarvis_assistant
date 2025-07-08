#!/bin/bash
# Script pour mettre à jour CHANGELOG.md avec les commits depuis la dernière release

set -e

# Trouver le dernier tag Git (release)
LAST_TAG=$(git describe --abbrev=0 --tags 2>/dev/null || true)

# Récupérer la liste des commits depuis la dernière release
if [ -n "$LAST_TAG" ]; then
  COMMITS=$(git log $LAST_TAG..HEAD --pretty=format:'- %s (%h)')
else
  COMMITS=$(git log --pretty=format:'- %s (%h)')
fi

if [ -z "$COMMITS" ]; then
  echo "Aucun nouveau commit depuis la dernière release ($LAST_TAG)."
  exit 0
fi

# Préparer le bloc à insérer
TMPFILE=$(mktemp)
echo "### Changed" > $TMPFILE
echo "$COMMITS" >> $TMPFILE
echo "" >> $TMPFILE

# Insérer sous la section Unreleased
sed -i "/## \[Unreleased\]/r $TMPFILE" CHANGELOG.md

rm $TMPFILE

echo "CHANGELOG.md mis à jour depuis $LAST_TAG."
