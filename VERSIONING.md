# Versioning System

## Overview

The Cocktail Machine project now uses a centralized versioning system to manage versions across all components consistently.

## Files Structure

```
├── VERSION                           # Main project version (1.0.5)
├── scripts/version.sh               # Version management script
├── web/VERSION                      # Web deployment version (with git hash)
├── web/package.json                 # Web dashboard package version
├── web/LATEST_DEPLOYMENT.json       # Latest deployment metadata
├── node-red/settings/package.json   # Node-RED package version
├── deployment/setup-ultimate.sh     # Contains script version
└── scripts/setup-ultimate.sh        # Contains script version
```

## Current Versions

### Main Project Version
- **Location**: `VERSION`
- **Current**: `1.0.5`
- **Format**: `X.Y.Z` (Semantic Versioning)

### Component Versions
- **Setup Scripts**: `2025.09.07-v1.0.4` + `Build-005`
- **Web Dashboard**: `1.0.0` (package.json)
- **Web Deployment**: `v2025.09.07.minor-b844f12` (with git hash)
- **Node-RED**: `1.0.0` (package.json)

## Version Management Script

### Usage

```bash
# Show current versions
./scripts/version.sh show

# Get main project version
./scripts/version.sh get

# Set specific version
./scripts/version.sh set 1.2.3

# Bump version
./scripts/version.sh bump patch    # 1.0.5 -> 1.0.6
./scripts/version.sh bump minor    # 1.0.5 -> 1.1.0
./scripts/version.sh bump major    # 1.0.5 -> 2.0.0

# Sync all components to main version
./scripts/version.sh sync
```

### What the Script Does

When you bump or set a version, it automatically updates:

1. **Main VERSION file**: Sets the new version
2. **Setup scripts**: Updates `SCRIPT_VERSION` with date + version format
3. **Web package.json**: Updates version field
4. **Node-RED package.json**: Updates version field  
5. **Web VERSION file**: Updates with date version + git hash
6. **Script build numbers**: Generates new build numbers

## Version Formats

### Main Project
- **Format**: `X.Y.Z` (e.g., `1.0.5`)
- **File**: `VERSION`

### Setup Scripts
- **Format**: `YYYY.MM.DD-vX.Y.Z` (e.g., `2025.09.07-v1.0.5`)
- **Build**: `Build-XXX` (auto-generated)
- **Files**: `deployment/setup-ultimate.sh`, `scripts/setup-ultimate.sh`

### Web Deployment
- **Format**: `vYYYY.MM.DD-vX.Y.Z-githash` (e.g., `v2025.09.07-v1.0.5-abc1234`)
- **File**: `web/VERSION`

### Package.json Files
- **Format**: `X.Y.Z` (e.g., `1.0.5`)
- **Files**: `web/package.json`, `node-red/settings/package.json`

## Workflow

### For Regular Updates
1. Make your changes
2. Run `./scripts/version.sh bump patch` (or minor/major)
3. Commit changes including version updates
4. Push to repository

### For Setting Specific Version
1. Run `./scripts/version.sh set 1.2.3`
2. Commit the version changes
3. Push to repository

### For Checking Versions
```bash
# Quick check of main version
./scripts/version.sh get

# Detailed view of all component versions
./scripts/version.sh show
```

## Integration with CI/CD

The version management script can be integrated into GitHub Actions:

```yaml
- name: Bump version
  run: |
    chmod +x scripts/version.sh
    ./scripts/version.sh bump patch
    
- name: Commit version changes
  run: |
    git config --local user.email "action@github.com"
    git config --local user.name "GitHub Action"
    git add .
    git commit -m "Bump version to $(cat VERSION)" || exit 0
```

## Benefits

1. **Consistency**: All components use the same base version
2. **Automation**: No manual version updates in multiple files
3. **Traceability**: Clear version history and component mapping
4. **Semantic Versioning**: Proper major.minor.patch versioning
5. **Git Integration**: Automatic git hash inclusion in deployment versions

## Migration Notes

If you have existing version inconsistencies:

```bash
# Sync all components to current main version
./scripts/version.sh sync

# Or set a new baseline version
./scripts/version.sh set 1.0.0
```

This will update all component versions to match the main project version.
