# 📱 Cocktail Machine - How to Update Your Dashboard

*Easy steps for Pi users to keep your cocktail machine up-to-date with the latest features!*

## 🎯 Quick Update (Recommended)

The easiest way to update your cocktail machine dashboard:

### Method 1: Using the Web Interface
1. **Open your browser** and go to: `http://your-pi-ip:1880/ui` 
2. **Click the "Updates" tab** (second tab from the top)
3. **Click "Install Update"** if an update is available
4. **Wait** for the update to complete (usually 1-2 minutes)
5. **Refresh your browser** to see the new dashboard

> 💡 **Tip:** Your Pi's IP address is usually something like `192.168.1.100`. You can find it by running `hostname -I` on the Pi.

### Method 2: One Command Update
If you prefer the command line, SSH to your Pi and run:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/sebastienlepoder/cocktail-deploy/main/scripts/quick-update.sh)"
```

That's it! ✨

## 🔍 Check Your Current Version

To see what version you're currently running:

### Via Web Interface:
1. Go to `http://your-pi-ip:1880/ui`
2. Click "Updates" tab
3. Your current version is shown at the top

### Via Command Line:
```bash
cat /opt/webroot/VERSION
```

## ⚠️ What to Expect During Updates

- **Duration:** Updates typically take 1-3 minutes
- **Downtime:** The dashboard may be briefly unavailable (10-30 seconds)
- **Backup:** Automatic backup is created before each update
- **Safety:** You can always rollback if something goes wrong

## 🆘 Troubleshooting

### Update Button Grayed Out?
- Make sure your Pi has internet connection
- Wait a few minutes - the system checks for updates every 10 minutes
- Try refreshing the page

### Can't Access the Web Interface?
```bash
# Check if Node-RED is running
sudo systemctl status nodered

# If not running, start it
sudo systemctl start nodered

# Then try accessing http://your-pi-ip:1880/ui again
```

### Manual Update Command Not Working?
```bash
# Try the direct update script
sudo /opt/scripts/update_dashboard.sh

# Or check internet connection
ping google.com
```

### Still Having Issues?
1. **Restart your Pi:** `sudo reboot`
2. **Check logs:** `journalctl -u nodered -f`
3. **Contact support** with your error messages

## 📋 Update History

Each update includes:
- 🔄 **New features** and improvements
- 🐛 **Bug fixes** and stability updates
- 🎨 **UI enhancements** and better user experience
- 🔒 **Security updates** when needed

## 🎛️ Advanced Options

### Check for Updates Manually
```bash
# Check what updates are available
curl http://localhost:1880/api/update/status
```

### Update to Specific Version
```bash
# If you know the version number
sudo /opt/scripts/update_dashboard.sh v2024.12.15-abc123
```

### View Backups
```bash
# See all your backups
ls -la /opt/backup/

# Restore from backup if needed (replace with your backup name)
sudo cp -r /opt/backup/dashboard_backup_v1.0.0_20241215_103000/webroot/* /opt/webroot/
sudo systemctl restart nginx
```

## 📞 Need Help?

- **Node-RED Dashboard:** `http://your-pi-ip:1880/ui`
- **System Logs:** `journalctl -u nodered -f` 
- **Restart Services:** `sudo systemctl restart nodered nginx`
- **Reboot Pi:** `sudo reboot`

---

## 🎉 That's It!

Your cocktail machine is designed to update itself automatically. Just keep your Pi connected to the internet, and you'll always have the latest features and improvements!

**Happy mixing! 🍹**
