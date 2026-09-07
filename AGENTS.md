
## Build workflow

For each user-requested app change, increment CFBundleVersion in scripts/package_app.sh. Package and update /Applications/Mosaic.app, then verify its installed build number so the user can identify the changed app. Preserve a backup when replacing the installed app.
