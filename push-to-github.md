# Push to GitHub Instructions

## Step 1: Create the Repository on GitHub

Go to https://github.com/new and create a new repository with these settings:

- **Repository name**: `cocktail-machine`
- **Description**: "Automated cocktail dispensing system with ESP32 modules and Raspberry Pi controller"
- **Visibility**: Public (or Private if you prefer)
- **DO NOT** initialize with README, .gitignore, or license (we already have these)

## Step 2: Push Your Code

After creating the empty repository on GitHub, run this command in your terminal:

```bash
git push -u origin main
```

If you get an authentication error, you'll need to use a Personal Access Token:

1. Go to https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. Give it a name like "cocktail-machine-push"
4. Select scopes: `repo` (full control)
5. Generate the token and copy it
6. When Git asks for password, paste the token (not your GitHub password)

## Alternative: Using GitHub CLI

If you want to create the repo from command line, install GitHub CLI first:

```powershell
# Install GitHub CLI using winget
winget install --id GitHub.cli

# Or using Chocolatey
choco install gh

# Then authenticate
gh auth login

# Create the repository
gh repo create cocktail-machine --public --source=. --remote=origin --push
```

## Manual Push Commands

If the above doesn't work, try these commands:

```bash
# Remove existing remote if needed
git remote remove origin

# Add the remote again
git remote add origin https://github.com/sebastienlepoder/cocktail-machine.git

# Push to main branch
git push -u origin main
```

## If You Get "Repository Not Found" Error

This means the repository doesn't exist on GitHub yet. You need to:
1. Create it on GitHub first (Step 1 above)
2. Or use the GitHub CLI method to create and push in one command

## After Successful Push

Your repository will be available at:
https://github.com/sebastienlepoder/cocktail-machine

The automated deployment script will work immediately:
```bash
curl -fsSL https://raw.githubusercontent.com/sebastienlepoder/cocktail-machine/main/deployment/setup-raspberry-pi.sh | bash
```
