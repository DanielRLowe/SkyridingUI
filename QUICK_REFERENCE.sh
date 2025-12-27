#!/bin/bash
# Quick Reference - SkyridingUI Release Commands

# 🚀 FIRST TIME SETUP
# -------------------
# 1. Initialize git repo
./setup_git.sh

# 2. Create repo on GitHub (if you don't have gh CLI)
#    Go to: https://github.com/new
#    Name: SkyridingUI
#    Public, no README
#    Then: git push -u origin main

# OR with GitHub CLI (easier):
gh repo create SkyridingUI --public --source=. --remote=origin --push


# 📦 EVERY RELEASE
# ----------------
# 1. Update version in SkyridingUI.toc
#    ## Version: 1.4.6

# 2. Update CHANGELOG.md with new version section

# 3. Run release script (does everything!)
./release.sh

# That's it! The script will:
# - Create SkyridingUI_X.X.X.zip
# - Commit changes
# - Create git tag
# - Push to GitHub
# - Create GitHub release (if gh CLI installed)


# 🔧 OPTIONAL: AUTOMATION SETUP
# ------------------------------

# Wago Addons (Easiest - no API needed!)
# 1. Go to https://addons.wago.io/
# 2. Sign in with GitHub
# 3. Add project, link to your repo
# 4. Enable "Monitor GitHub Releases"
# ✅ Done! Wago auto-updates on new releases

# CurseForge Option 1: Manual (Recommended)
# 1. Go to https://www.curseforge.com/
# 2. Create addon project
# 3. Upload SkyridingUI_X.X.X.zip for each release
# ✅ Simple and works perfectly

# CurseForge Option 2: Automated
# 1. Get API token from https://authors.curseforge.com/account/api-tokens
# 2. Get project ID from your addon page
# 3. Add to GitHub:
gh secret set CURSEFORGE_TOKEN
gh variable set CURSEFORGE_PROJECT_ID --body "YOUR_ID"
# ✅ Auto-uploads on each release


# 🆘 TROUBLESHOOTING
# ------------------

# Fix: "Not a git repository"
git init
git remote add origin https://github.com/USERNAME/SkyridingUI.git

# Fix: "Permission denied: ./release.sh"
chmod +x release.sh setup_git.sh

# Fix: "gh: command not found"
brew install gh
gh auth login

# Check GitHub Actions status
gh workflow view release


# 📋 USEFUL GIT COMMANDS
# ----------------------

# Check status
git status

# See remote URL
git remote -v

# List tags
git tag -l

# Delete a tag (if you made a mistake)
git tag -d v1.4.5                    # Delete locally
git push origin --delete v1.4.5      # Delete on GitHub

# View commit history
git log --oneline

# Undo last commit (keep changes)
git reset --soft HEAD^

# View files in last commit
git show --name-only
