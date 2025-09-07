# 🎨 Web Dashboard Development Workflow

This document explains the complete workflow for developing and deploying the web dashboard using a 4-repository system.

## 🏗️ Repository Structure

The cocktail machine uses a **4-repository deployment model** for web dashboard development:

| Repository | Type | Purpose | URL |
|------------|------|---------|-----|
| `cocktail-slider-display` | **Web Dev** | React dashboard development | https://github.com/sebastienlepoder/cocktail-slider-display |
| `cocktail-machine-dev` | **Main Dev** | Backend + deployment orchestration | https://github.com/sebastienlepoder/cocktail-machine-dev |
| `cocktail-machine-prod` | **Production** | Built releases for Pi users | https://github.com/sebastienlepoder/cocktail-machine-prod |
| `warp-cocktail-machine` | **Local Dev** | Your development environment | *This repo (synced via Warp)* |

## 🔄 Complete Deployment Flow

```
🎨 Web Dashboard      🚀 Main Dev        🏭 Production       🤖 Pi Users
(cocktail-slider-    (cocktail-         (cocktail-machine-prod)  (Raspberry Pi)
display)             machine)           │                  │
│                    │                  │                  │
│-- Build & Pack --▶│                  │                  │
                     │-- Dev → Prod --▶│                  │
                                        │-- Auto notify -▶│
```

### Flow Explanation:

1. **🎨 Web Development** - Develop React dashboard in `cocktail-slider-display`
2. **📦 Build & Package** - GitHub Actions builds, packages, and deploys to `cocktail-machine-dev` 
3. **🔄 Integration** - Backend systems (Node-RED, MQTT) integrate in `cocktail-machine-dev`
4. **🚀 Production Deploy** - Manual deployment from `cocktail-machine-dev` to `cocktail-machine-prod`
5. **📱 User Updates** - Pi users get automatic notifications and one-click updates

## 🎨 Web Dashboard Development Process

### 1. Setup Your Web Dashboard Repository

In your `cocktail-slider-display` repository, you need:

#### Required GitHub Secret
- **`DEPLOY_TOKEN`**: Personal Access Token with `repo` permissions (same as your other repos)

#### Required Package.json Scripts
```json
{
  "scripts": {
    "build": "react-scripts build",
    "start": "react-scripts start",
    "test": "react-scripts test"
  }
}
```

### 2. Create the Workflow File

In your `cocktail-slider-display` repository, create:
`.github/workflows/web-to-dev.yml`

*Copy the content from the `web-to-dev.yml` file provided above.*

### 3. Web Development Workflow

```bash
# 1. Develop your React dashboard locally
cd cocktail-slider-display
npm start  # Development server at http://localhost:3000

# 2. Test your changes
npm run build  # Make sure it builds successfully

# 3. Commit your changes
git add .
git commit -m "Add new cocktail mixing interface"
git push origin main
```

### 4. Deploy Web Dashboard to Dev

When your web dashboard is ready to integrate with the backend:

1. **Go to GitHub Actions** in your `cocktail-slider-display` repository
2. **Select "🎨 Web Dashboard → Dev Deployment"** workflow  
3. **Click "Run workflow"**
4. **Fill out the form:**
   - **Release type**: `minor` (normal), `patch` (bugfix), `major` (breaking changes)
   - **Release notes**: Describe what changed in the dashboard
   - **Force deploy**: Only if no changes detected
5. **Click "Run workflow"** button

**What happens:**
- ✅ Builds your React dashboard (`npm run build`)
- ✅ Creates versioned package (e.g., `dashboard-v2025.01.06.minor-abc1234.tar.gz`)
- ✅ Deploys package to `cocktail-machine-dev` dev repository
- ✅ Creates deployment metadata for integration

### 5. Integration Testing

After web deployment, test the integration:

1. **Check the `cocktail-machine-dev` repository** for your web package
2. **Test locally** if you have the backend running
3. **Make adjustments** to backend integration if needed

### 6. Production Deployment

When both web dashboard and backend are ready for users:

1. **Go to GitHub Actions** in your `cocktail-machine-dev` repository
2. **Select "🚀 Dev → Prod Deployment"** workflow
3. **Click "Run workflow"**
4. **Fill out the deployment form** with production release notes
5. **Click "Run workflow"** button

**What happens:**
- ✅ Extracts your pre-packaged web dashboard 
- ✅ Combines with backend components (scripts, Node-RED, etc.)
- ✅ Creates production release in `cocktail-machine-prod`
- ✅ Notifies Pi users for automatic updates

## 📋 Version Management

### Web Dashboard Versioning
Web versions follow: `vYYYY.MM.DD.{type}-{commit}`

Examples:
- `v2025.01.06.minor-abc1234` - Minor release on Jan 6, 2025
- `v2025.01.06.patch-def5678` - Patch release same day
- `v2025.01.07.major-ghi9012` - Major release next day

### Production Integration Versioning  
Production versions follow: `vYYYY.MM.DD-HHMM-{commit}`

Examples:
- `v2025.01.06-1430-xyz7890` - Production release at 14:30

## 🔧 Development Best Practices

### For Web Dashboard Development

1. **Test Builds Locally**
   ```bash
   npm run build
   # Check that build/ or dist/ directory is created
   ```

2. **Use Semantic Release Types**
   - **patch**: Bug fixes, minor tweaks
   - **minor**: New features, UI improvements  
   - **major**: Breaking changes, major redesigns

3. **Write Descriptive Release Notes**
   ```
   ✅ Good: "Added cocktail recipe search and filtering"
   ❌ Bad: "Updated UI"
   ```

4. **Test Responsive Design**
   - Target: 800x480 (5" Pi display)
   - Test touch interactions
   - Ensure kiosk-friendly design

### For Production Deployment

1. **Test Integration First**
   - Verify web dashboard works with Node-RED
   - Test MQTT connectivity if needed
   - Check API endpoints

2. **Coordinate Release Notes**
   - Include both web dashboard and backend changes
   - Mention any breaking changes or new features
   - Provide clear user-facing benefits

## 🛠️ Troubleshooting

### Web Dashboard Build Issues

**Problem**: Build fails in GitHub Actions
```bash
# Check your package.json build script
npm run build  # Test locally first
```

**Problem**: Package not found in dev repository
```bash
# Check the web-to-dev.yml workflow logs
# Verify DEPLOY_TOKEN permissions
# Check if web/packages/ directory exists in cocktail-machine-dev
```

### Integration Issues

**Problem**: Dashboard not showing in production
```bash
# Check if web package was extracted correctly
# Verify prod-deploy/web/ contains your built files
# Check versions.json for correct web version
```

**Problem**: API endpoints not working
```bash
# Ensure your dashboard points to correct backend URLs
# Check Node-RED flows are deployed and running
# Verify MQTT broker connectivity
```

### Development Workflow Issues

**Problem**: Changes not reflected in production
```bash
# Ensure you ran web-to-dev deployment first
# Then run dev-to-prod deployment  
# Check both workflows completed successfully
```

## 📁 File Structure Examples

### Web Dashboard Repository (`cocktail-slider-display`)
```
cocktail-slider-display/
├── .github/workflows/
│   └── web-to-dev.yml          # Web deployment workflow
├── src/                        # React source code
├── public/                     # Static files
├── build/                      # Built dashboard (after npm run build)
├── package.json                # Dependencies and scripts  
└── README.md
```

### Dev Repository After Web Deployment (`cocktail-machine-dev`)
```
cocktail-machine-dev/
├── web/
│   ├── packages/
│   │   └── dashboard-v2025.01.06.minor-abc1234.tar.gz
│   ├── LATEST_DEPLOYMENT.json  # Deployment metadata
│   └── VERSION                 # Current web version
├── node-red/                   # Backend flows
├── deployment/                 # Pi setup scripts  
└── .github/workflows/
    └── dev-to-prod.yml         # Production deployment
```

### Production Repository (`cocktail-machine-prod`)
```  
cocktail-machine-prod/
├── web/                        # Extracted dashboard files
│   ├── index.html
│   ├── static/
│   ├── VERSION
│   └── versions.json
├── scripts/                    # Pi installation scripts
├── kiosk/                      # Kiosk configuration
└── web.tar.gz                  # Compressed web archive
```

## 🎯 Quick Reference Commands

### Develop Web Dashboard
```bash
# In cocktail-slider-display repository
npm start                       # Development server
npm run build                   # Test production build
git add . && git commit -m "..." && git push  # Save changes
# → Go to GitHub Actions → Run "Web Dashboard → Dev Deployment"
```

### Deploy to Production
```bash
# After web dashboard is deployed to cocktail-machine-dev
# → Go to cocktail-machine-dev GitHub Actions
# → Run "Dev → Prod Deployment" 
# → Pi users get automatic update notifications
```

### Check Deployment Status
```bash
# Check web deployment
curl https://raw.githubusercontent.com/sebastienlepoder/cocktail-machine-dev/main/web/LATEST_DEPLOYMENT.json

# Check production deployment  
curl https://raw.githubusercontent.com/sebastienlepoder/cocktail-machine-prod/main/web/versions.json
```

---

## 🎉 Summary

Your web development workflow is now:

1. **🎨 Develop** React dashboard in `cocktail-slider-display`
2. **📦 Build & Deploy** web dashboard to `cocktail-machine-dev` via GitHub Actions
3. **🔄 Integrate** with backend systems in `cocktail-machine-dev`
4. **🚀 Deploy** complete system to `cocktail-machine-prod` via GitHub Actions  
5. **📱 Users Update** via Node-RED dashboard or automatic notifications

This gives you **controlled, versioned deployments** while maintaining **separation of concerns** between your web frontend and backend systems!
