'use strict';
// electron-builder afterAllArtifactBuild hook: sign + notarize + staple each .dmg
// so the disk image itself passes Gatekeeper, not just the app inside it. The
// afterSign hook (notarize.js) already handled the .app; this finishes the DMG,
// which only exists after artifacts are built.
//
// Reads the same "saetta-notary" notarytool keychain profile. SKIP_NOTARIZE=1 skips.
const { execFileSync } = require('node:child_process');

const PROFILE = 'saetta-notary';
const IDENTITY = 'Developer ID Application: Jordan Babev (UWJSLFQDGL)';

exports.default = async function (buildResult) {
  if (process.env.SKIP_NOTARIZE === '1') {
    console.log('[notarize-dmg] SKIP_NOTARIZE=1 — leaving dmg unsigned');
    return [];
  }
  const dmgs = (buildResult.artifactPaths || []).filter((p) => p.endsWith('.dmg'));
  for (const dmg of dmgs) {
    console.log(`[notarize-dmg] signing ${dmg}`);
    execFileSync('codesign', ['--force', '--timestamp', '--sign', IDENTITY, dmg], { stdio: 'inherit' });
    console.log(`[notarize-dmg] submitting ${dmg} to Apple (a few minutes)…`);
    execFileSync('xcrun', ['notarytool', 'submit', dmg, '--keychain-profile', PROFILE, '--wait'], { stdio: 'inherit' });
    console.log(`[notarize-dmg] stapling ${dmg}`);
    execFileSync('xcrun', ['stapler', 'staple', dmg], { stdio: 'inherit' });
  }
  return [];
};
