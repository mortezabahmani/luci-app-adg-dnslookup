# Workspace Rules for luci-app-adg-dnslookup

This file defines project-specific rules that all AI agents must follow when operating in this workspace.

## 🚀 Automated Release DevOps
Whenever you implement an approved bug fix or feature, you **MUST** automatically run the release pipeline without waiting for the user to explicitly ask you to build or push.

**Follow these exact steps:**
1. Update `README.md` and `README-FA.md` if the installation instructions or version numbers need changing.
2. Update the `docs/memory.md` file if a significant bug was fixed or an architectural decision was made.
3. Add all changes (`git add .`) and commit them with a descriptive message.
4. **DO NOT** build the `.ipk` or `.apk` files locally.
5. Create a new Git Tag matching the version (e.g., `git tag v2.0.1`).
6. Push the code and the tags: `git push origin main --tags`

**Why?** Pushing the tag automatically triggers the GitHub Actions CI/CD pipeline (`.github/workflows/release.yml`) which handles building the Alpine/OpenWrt packages and publishing the GitHub Release.

## 📝 Ponytail Principle
Keep code modifications as lean and minimalist as possible. Avoid over-engineering solutions. Check `docs/memory.md` before making assumptions about OpenWrt architectures (e.g., `wget` bugs, Alpine packaging).
