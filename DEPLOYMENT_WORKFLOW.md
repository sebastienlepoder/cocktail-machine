# 🚀 Developer Deployment Workflow

*Step-by-step guide for deploying your cocktail machine updates to Pi users*

---

## 📋 **When is Your Dev Repo Ready to Deploy?**

Before deploying, ensure you have:
- ✅ **Tested** your changes locally
- ✅ **Web dashboard** working (if modified)
- ✅ **Node-RED flows** functional (if updated)
- ✅ **Scripts** tested on development environment
- ✅ **Documentation** updated if needed

---

## 🎯 **Deployment Methods: You Have 3 Options**

### **Method 1: Automatic Deployment (Recommended)**
*Deploy automatically when you push changes*

```bash
# Work on your changes
git add .
git commit -m "Add new cocktail recipe feature"
git push origin main
```

**What happens:**
- GitHub Actions automatically detects changes to `web/`, `scripts/`, `kiosk/`, `deployment/`
- Builds and deploys within 1-2 minutes
- Pi users get notified automatically
- **Zero manual work needed!**

**When this triggers:**
- Changes to `web/**` (dashboard files)
- Changes to `scripts/**` (installation scripts)  
- Changes to `kiosk/**` (kiosk configuration)
- Changes to `deployment/**` (Pi setup files)
- Changes to `package*.json` (dependencies)

### **Method 2: Manual Deployment**
*Deploy manually when YOU decide it's ready*

```bash
# Use GitHub CLI to trigger deployment
gh workflow run deploy-dashboard.yml

# Or with force deployment (deploys even if no changes)
gh workflow run deploy-dashboard.yml --field force_deploy=true
```

**When to use:**
- You want to control exactly when deployment happens
- You made changes outside the auto-trigger paths
- You want to test the deployment process

### **Method 3: Release Tags** *(Future Enhancement)*
*Deploy only when you create release tags*

```bash
# Create a release tag when ready to deploy
git tag -a v2.1.0 -m "Release v2.1.0: New cocktail recipes and improved UI"
git push origin v2.1.0
```

*Note: This method isn't implemented yet but could be added to the workflow*

---

## 🔄 **Complete Development & Deployment Process**

### **Step 1: Development** 
```bash
# Work on your local development
cd /path/to/warp-cocktail-machine

# Make your changes
# - Update web dashboard
# - Modify Node-RED flows  
# - Fix bugs, add features
# - Test locally

# Test your changes
docker-compose up -d  # Test locally first
```

### **Step 2: Prepare for Deployment**
```bash
# Check what will be deployed
git status
git diff --name-only

# Make sure changes are in deployable paths:
# ✅ web/             (triggers deployment)
# ✅ scripts/         (triggers deployment)  
# ✅ deployment/      (triggers deployment)
# ✅ kiosk/           (triggers deployment)
# ❌ .github/         (doesn't trigger, manual needed)
# ❌ docs/            (doesn't trigger, manual needed)
```

### **Step 3: Deploy Decision**

**Option A - Auto Deploy:**
```bash
# Commit and push (triggers automatic deployment)
git add .
git commit -m "🍹 Add Mojito recipe and improve pump timing

- New mojito recipe with proper ratios
- Improved pump timing for better consistency  
- Fixed volume calculation bug
- Updated UI with better error messages"
git push origin main
```

**Option B - Manual Deploy:**
```bash
# Commit but don't push yet
git add .
git commit -m "🍹 Add experimental features"

# Deploy manually when ready
gh workflow run deploy-dashboard.yml --field force_deploy=true

# Then push your commits
git push origin main
```

### **Step 4: Monitor Deployment**
```bash
# Watch the deployment progress
gh run list --workflow="deploy-dashboard.yml" --limit 1

# View detailed logs if needed
gh run view --log

# Check deployment was successful
curl -s https://raw.githubusercontent.com/sebastienlepoder/cocktail-deploy/main/web/VERSION
```

### **Step 5: Verify Pi Users Can Update**
```bash
# Test the update API endpoint
curl -s https://raw.githubusercontent.com/sebastienlepoder/cocktail-deploy/main/web/versions.json

# The Node-RED update system will automatically:
# ✅ Check for new version every 10 minutes
# ✅ Show "Install Update" button in dashboard
# ✅ Allow users to update with one click
```

---

## 📊 **Deployment Monitoring & Status**

### **Check Deployment Status:**
```bash
# View recent deployments
gh run list --workflow="deploy-dashboard.yml" --limit 5

# Check if deployment is running
gh run list --workflow="deploy-dashboard.yml" | head -1

# View deployment details
gh run view WORKFLOW_ID
```

### **Check What Was Deployed:**
```bash
# See current deployed version
curl -s https://raw.githubusercontent.com/sebastienlepoder/cocktail-deploy/main/web/VERSION

# See deployment details  
curl -s https://raw.githubusercontent.com/sebastienlepoder/cocktail-deploy/main/web/versions.json | jq

# List all deployed files
curl -s https://api.github.com/repos/sebastienlepoder/cocktail-deploy/contents | jq '.[].name'
```

---

## ⚡ **Quick Deploy Commands**

### **Emergency/Hotfix Deploy:**
```bash
# Quick fix and deploy
git add . && git commit -m "🚨 Hotfix: Critical bug fix" && git push

# Force immediate deployment
gh workflow run deploy-dashboard.yml --field force_deploy=true
```

### **Test Deploy (without Pi user impact):**
```bash
# Deploy to test the system (Pi users won't be affected immediately)
gh workflow run deploy-dashboard.yml --field force_deploy=true

# Pi users still need to manually click "Install Update"
# So you can test the deployment worked without forcing updates
```

---

## 🎯 **Best Practices for Deployments**

### **✅ DO:**
- **Test locally first** before deploying
- **Use descriptive commit messages** (become release notes)
- **Deploy during low-usage times** (updates restart services briefly)  
- **Monitor deployment completion** before announcing to users
- **Keep deployment commits focused** (one feature per deploy)

### **❌ DON'T:**
- Deploy untested changes
- Deploy multiple unrelated changes together
- Force deploy without understanding what changed
- Deploy during peak usage times
- Ignore deployment failures

---

## 🔧 **Troubleshooting Deployments**

### **Deployment Failed:**
```bash
# Check failure reason
gh run view --log-failed

# Common issues:
# - Node.js build errors → Fix package.json or build scripts
# - File copy errors → Check file permissions
# - GitHub token issues → Verify DEPLOY_TOKEN secret
```

### **Deployment Succeeded but Pi Users Can't Update:**
```bash
# Check deployed version
curl https://raw.githubusercontent.com/sebastienlepoder/cocktail-deploy/main/web/versions.json

# Check Pi can reach deployment repo
ssh pi@your-pi-ip "curl -I https://raw.githubusercontent.com/sebastienlepoder/cocktail-deploy/main/web/VERSION"

# Check Node-RED update system
ssh pi@your-pi-ip "curl http://localhost:1880/api/update/status"
```

### **Roll Back Deployment:**
```bash
# Find previous version
gh run list --workflow="deploy-dashboard.yml" --limit 10

# Get previous commit hash
git log --oneline -5

# Revert to previous commit and redeploy
git revert HEAD
git push origin main  # This triggers new deployment with rollback
```

---

## 📈 **Deployment History & Tracking**

### **View Deployment History:**
```bash
# See all deployments
gh run list --workflow="deploy-dashboard.yml" --limit 20

# See deployment repository commits
cd /path/to/cocktail-deploy
git log --oneline --graph
```

### **Track Version Changes:**
```bash
# See version progression
cd /path/to/cocktail-deploy
git log --oneline web/VERSION

# Compare versions
git diff HEAD~1..HEAD web/versions.json
```

---

## 🎉 **Summary: Your Deployment Options**

| Method | When to Use | Command | Pi User Impact |
|--------|-------------|---------|----------------|
| **Auto Deploy** | Regular updates, tested changes | `git push` | Notified in 10min |
| **Manual Deploy** | Controlled timing, special releases | `gh workflow run deploy-dashboard.yml` | Notified in 10min |
| **Force Deploy** | Testing, no changes made | `gh workflow run --field force_deploy=true` | Notified in 10min |

**The beauty of this system:** Once you deploy, Pi users get automatic notifications and can update with a single click! 🚀

Your development workflow is now streamlined:
**Code → Test → Deploy → Users automatically notified → One-click updates**
