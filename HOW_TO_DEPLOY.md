# 🚀 How to Deploy from Dev to Production

*Simple 3-step process to deploy your cocktail machine to production when ready*

---

## 🎯 **When to Deploy to Production**

Deploy when your dev repo (`cocktail-machine-dev`) is ready for Pi users:

- ✅ **Features tested** and working locally
- ✅ **Web dashboard** functional (if updated)  
- ✅ **Node-RED flows** operational (if changed)
- ✅ **Scripts verified** on development environment
- ✅ **Ready for Pi users** to download and use

---

## 📋 **3-Step Deployment Process**

### **Step 1: Go to GitHub Actions**
1. Open your browser to: https://github.com/sebastienlepoder/cocktail-machine-dev
2. Click **Actions** tab
3. Click **"🚀 Dev → Prod Deployment"** workflow

### **Step 2: Run Workflow**
1. Click **"Run workflow"** button (on the right)
2. Fill out the form:
   - **Release type:** Choose `minor` (normal), `patch` (bugfix), or `major` (big changes)
   - **Release notes:** Describe what's new (e.g., "Added mojito recipe, fixed pump timing")
   - **Force deploy:** Leave unchecked (unless you want to deploy without changes)
3. Click **"Run workflow"** green button

### **Step 3: Wait & Verify**
1. **Wait 2-3 minutes** for deployment to complete
2. **Check the green checkmark** appears  
3. **Pi users automatically get notified** within 10 minutes!

---

## 📝 **Example Deployment Form**

```
Branch: main (selected)
Release type: minor ✓
Release notes: Added new cocktail recipes and improved UI responsiveness. Fixed pump timing issues and enhanced error handling.
Force deployment: ☐ (unchecked)
```

**Then click:** "Run workflow" 🚀

---

## ✅ **What Happens During Deployment**

1. **📥 Grabs** your latest dev code  
2. **🔨 Builds** web dashboard (if needed)
3. **📦 Creates** production package with version number
4. **🚀 Deploys** to `cocktail-machine-prod` repository  
5. **📢 Notifies** Pi users automatically
6. **📊 Shows** deployment summary

---

## 🏷️ **Version Numbers**

Your production releases get automatic version numbers:

- **Minor release:** `v2025.09.06-1520-a1b2c3d` (normal updates)
- **Patch release:** `v2025.09.06-patch-a1b2c3d` (bug fixes)
- **Major release:** `v2025.09.06-major-a1b2c3d` (big changes)

---

## 📊 **After Deployment**

### **Verify Success:**
- Green checkmark ✅ in Actions tab
- New files appear in [`cocktail-machine-prod`](https://github.com/sebastienlepoder/cocktail-machine-prod) repo
- Version number updated in `web/VERSION`

### **Pi Users Can:**
- **See "Install Update"** button in Node-RED dashboard (within 10 minutes)  
- **One-click update** to your latest release
- **Fresh install** using new production version

---

## 🚨 **Emergency Deployment**

For critical fixes:

1. **Fix the issue** in your dev repo
2. **Commit changes** (Warp will sync to GitHub)
3. **Go to Actions** → **"🚀 Dev → Prod Deployment"**
4. **Select `patch`** release type
5. **Write:** "Critical bugfix - [describe issue]"
6. **Deploy immediately** 🚀

---

## 🔍 **Troubleshooting**

### **Deployment Failed (❌):**
- Click the failed run to see error details
- Usually build errors or missing files
- Fix in dev repo and try again

### **No Changes Detected:**
- Check the **"Force deployment"** option
- Or make a small change in your dev repo first

### **Pi Users Not Getting Updates:**
- Verify deployment succeeded (green checkmark)
- Check [`cocktail-machine-prod`](https://github.com/sebastienlepoder/cocktail-machine-prod) repo has new files
- Pi users need internet connection for update notifications

---

## 🎉 **That's It!**

Your deployment process is now:
1. **Develop** in local repo → Warp syncs to GitHub
2. **Ready for production?** Go to Actions → Run "Dev → Prod Deployment"  
3. **Pi users get notified** automatically!

**Simple, controlled, and safe! 🚀**
