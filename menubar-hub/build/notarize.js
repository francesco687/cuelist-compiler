'use strict';
// electron-builder afterSign hook: notarize the signed .app with Apple, then staple
// the ticket so it passes Gatekeeper offline (USB / no internet on the target Mac).
//
// Credentials are read from a notarytool *keychain profile* named "saetta-notary"
// (create once with `xcrun notarytool store-credentials saetta-notary ...`) so the
// app-specific password never lives in the repo, env, or shell history.
//
// Set SKIP_NOTARIZE=1 to build a signed-but-not-notarized app (faster local checks).
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { notarize } = require('@electron/notarize');

const PROFILE = 'saetta-notary';

exports.default = async function notarizing(context) {
  const { electronPlatformName, appOutDir } = context;
  if (electronPlatformName !== 'darwin') return;
  if (process.env.SKIP_NOTARIZE === '1') {
    console.log('[notarize] SKIP_NOTARIZE=1 — signed only, not notarized');
    return;
  }

  const appName = context.packager.appInfo.productFilename; // "Saetta Hub"
  const appPath = path.join(appOutDir, `${appName}.app`);

  console.log(`[notarize] submitting "${appPath}" via keychain profile "${PROFILE}" (this can take a few minutes)…`);
  await notarize({ tool: 'notarytool', appPath, keychainProfile: PROFILE });

  console.log('[notarize] accepted — stapling ticket');
  execFileSync('xcrun', ['stapler', 'staple', appPath], { stdio: 'inherit' });
  console.log('[notarize] done');
};
