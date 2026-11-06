#!/usr/bin/env bash
# Voice.AI GitHub Pages One-Click Deployment Script
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "=================================================="
echo "  Deploying Voice.AI Website to GitHub Pages"
echo "=================================================="

# Ensure tokens and app companion are fresh in website/
cp "${ROOT_DIR}/tokens.css" "${ROOT_DIR}/website/tokens.css"
rm -rf "${ROOT_DIR}/website/app"
cp -r "${ROOT_DIR}/app" "${ROOT_DIR}/website/app"
touch "${ROOT_DIR}/website/.nojekyll"

# Re-split website subtree to local gh-pages branch
echo "Splitting website/ to gh-pages branch..."
git subtree split --prefix website -b gh-pages-temp

# Force update local gh-pages
git branch -D gh-pages || true
git branch -m gh-pages-temp gh-pages

# Push to origin gh-pages
echo "Pushing gh-pages to origin..."
git push origin gh-pages --force

echo "=================================================="
echo "  Deployment Push Completed Successfully!"
echo "  Live URL: https://mohit-jpg-dot.github.io/Voice.AI/"
echo "=================================================="

