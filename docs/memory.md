# Project Memory (luci-app-adg-dnslookup)

This file contains the historical context of the project, including bugs, architectural shifts, and DevOps workflows.

## Historical Bugs & Architectural Decisions

### 1. `wget` HTTP 302 Redirection Bug
- **Bug**: Older versions of OpenWrt (like 23.05) use BusyBox's `wget`. This stripped-down version of `wget` fails to properly handle HTTP 302 redirects from GitHub Releases and Amazon S3 buckets, leading to corrupt or zero-byte downloads.
- **Fix**: Replaced all `wget` installation commands in the README with `curl -L`. `curl` flawlessly handles redirects.

### 2. AdGuardHome Config File Path Chaos (`Config not found`)
- **Bug**: The plugin originally worked by manually appending IPs to the `AdGuardHome.yaml` file on the router. However, the path to this file varied wildly (`/etc/adguardhome.yaml`, `/etc/adguardhome/adguardhome.yaml`, `/opt/AdGuardHome/AdGuardHome.yaml`), meaning the script often failed with a `Config not found` error.
- **Fix**: In **v2.0.0**, the architecture was entirely rewritten. Instead of editing the YAML file and issuing a `reload` command, the script now uses the **AdGuardHome REST API** (`/control/rewrite/add` and `/control/rewrite/delete`). This eliminated the file-path dependency entirely and made the sync instant.

### 3. Binary Artifact Tracking
- **Bug**: Compiled `.ipk` and `.apk` files were accidentally tracked in the Git repository, bloating the history.
- **Fix**: They were removed via `git rm -f *.apk *.ipk` and added to `.gitignore`. Binaries are now exclusively attached to GitHub Releases.

## Build and Release Process

### Automated CI/CD (GitHub Actions)
The project now uses a fully automated CI/CD pipeline (`.github/workflows/release.yml`).

To release a new version:
1. Update `README.md` and `README-FA.md` with the new version strings in the install commands.
2. Commit your changes: `git commit -m "feat: description"`
3. Create a new tag: `git tag v2.0.1`
4. Push everything: `git push origin main --tags`

Once the tag is pushed, **GitHub Actions** will automatically:
- Spin up an Alpine Docker container.
- Build both the `.ipk` (using the local build script) and `.apk` (using Alpine's `abuild`).
- Create a GitHub Release and attach the compiled packages.

You **do not** need to run Docker locally to build releases anymore.
