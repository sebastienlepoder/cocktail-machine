# Cocktail Machine Kiosk Mode Setup

If the automatic setup isn't working, follow these manual steps to set up the kiosk mode with loading screen:

## Quick Fix for Current Issues

### 1. SSH into your Raspberry Pi
```bash
ssh pi@raspberrypi.local
```

### 2. Create the loading screen HTML
```bash
mkdir -p ~/.cocktail-machine-dev
nano ~/.cocktail-machine-dev/loading.html
```

Copy and paste this content:
```html
<!DOCTYPE html>
<html>
<head>
    <title>Cocktail Machine Loading</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100vh;
            overflow: hidden;
        }
        .container {
            text-align: center;
            animation: fadeIn 1s ease-in;
        }
        .logo {
            font-size: 80px;
            margin-bottom: 20px;
            animation: float 3s ease-in-out infinite;
        }
        h1 {
            font-size: 48px;
            margin-bottom: 20px;
            font-weight: 300;
        }
        .loader {
            width: 60px;
            height: 60px;
            border: 3px solid rgba(255,255,255,0.3);
            border-radius: 50%;
            border-top-color: white;
            animation: spin 1s linear infinite;
            margin: 40px auto;
        }
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
        @keyframes float {
            0%, 100% { transform: translateY(0px); }
            50% { transform: translateY(-20px); }
        }
        @keyframes fadeIn {
            from { opacity: 0; }
            to { opacity: 1; }
        }
    </style>
    <script>
        // Check if service is ready every 3 seconds
        setInterval(function() {
            fetch('http://localhost:3000')
                .then(response => {
                    if (response.ok) {
                        window.location.href = 'http://localhost:3000';
                    }
                })
                .catch(() => {});
        }, 3000);
    </script>
</head>
<body>
    <div class="container">
        <div class="logo">🍹</div>
        <h1>Cocktail Machine</h1>
        <div class="loader"></div>
        <p>Starting services...</p>
    </div>
</body>
</html>
```

Save and exit (Ctrl+X, Y, Enter).

### 3. Download and set up the kiosk script
```bash
cd ~/cocktail-machine-dev/deployment
wget https://raw.githubusercontent.com/sebastienlepoder/cocktail-machine-prod/main/scripts/start-kiosk.sh
chmod +x start-kiosk.sh
```

Or create it manually:
```bash
nano ~/cocktail-machine-dev/deployment/start-kiosk.sh
```

### 4. Set up auto-start using systemd (Recommended)

Create a systemd service for the kiosk:
```bash
sudo nano /etc/systemd/system/cocktail-kiosk.service
```

Add this content:
```ini
[Unit]
Description=Cocktail Machine Kiosk Display
After=graphical.target cocktail-machine-dev.service
Wants=graphical.target

[Service]
Type=simple
User=pi
Environment="DISPLAY=:0"
Environment="XAUTHORITY=/home/pi/.Xauthority"
ExecStartPre=/bin/sleep 10
ExecStart=/home/pi/cocktail-machine-dev/deployment/start-kiosk.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical.target
```

Enable the service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable cocktail-kiosk.service
```

### 5. Alternative: Use .bashrc for auto-start
If systemd doesn't work, add to your .bashrc:
```bash
echo 'if [ -z "$SSH_TTY" ] && [ "$TERM" = "linux" ]; then
    startx /home/pi/cocktail-machine-dev/deployment/start-kiosk.sh
fi' >> ~/.bashrc
```

### 6. Configure auto-login
```bash
sudo raspi-config
```
- Navigate to System Options > Boot / Auto Login
- Select "Desktop Autologin" or "Console Autologin"

### 7. Hide boot messages (optional)
```bash
# Backup and edit boot config
sudo cp /boot/cmdline.txt /boot/cmdline.txt.backup
sudo nano /boot/cmdline.txt
```

Add these parameters to the end of the line:
```
quiet splash loglevel=0 logo.nologo vt.global_cursor_default=0
```

### 8. Reboot
```bash
sudo reboot
```

## What Should Happen

1. **Power On**: Black screen (if quiet boot is configured)
2. **Boot**: System boots silently
3. **Auto-login**: Logs in automatically
4. **Loading Screen**: Beautiful loading screen appears immediately
5. **Service Check**: Script waits for backend to be ready
6. **Dashboard**: Automatically switches to dashboard when ready

## Troubleshooting

### If you see boot messages:
- Check if `/boot/cmdline.txt` or `/boot/firmware/cmdline.txt` has the quiet parameters
- Some newer Raspberry Pi OS versions use `/boot/firmware/cmdline.txt`

### If you see error 404:
- The loading screen isn't being shown
- Check if the loading.html file exists: `ls ~/.cocktail-machine-dev/loading.html`
- Try running the kiosk script manually: `DISPLAY=:0 ~/cocktail-machine-dev/deployment/start-kiosk.sh`

### If nothing starts automatically:
- Check if auto-login is configured: `systemctl status getty@tty1.service`
- Check if the kiosk service is running: `systemctl status cocktail-kiosk.service`
- Check logs: `journalctl -u cocktail-kiosk.service -f`

### Manual Testing
To test the kiosk mode manually:
```bash
# From SSH session
export DISPLAY=:0
~/cocktail-machine-dev/deployment/start-kiosk.sh
```

## Direct Browser Command
If you just want to start the browser directly (no loading screen):
```bash
DISPLAY=:0 chromium-browser --kiosk --noerrdialogs --disable-infobars http://localhost:3000
```
