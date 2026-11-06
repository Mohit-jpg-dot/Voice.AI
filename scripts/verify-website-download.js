#!/usr/bin/env node
/**
 * VoiceOS Website & Download Verification Script
 * Validates latest.json, verifies that the DMG exists, checks SHA-256 hash equality,
 * and confirms that website download links are functional and uncorrupted.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT_DIR = path.resolve(__dirname, '..');
const WEBSITE_DIR = path.join(ROOT_DIR, 'website');
const LATEST_JSON_PATH = path.join(WEBSITE_DIR, 'latest.json');
const APPCAST_PATH = path.join(WEBSITE_DIR, 'appcast.xml');

console.log("=================================================");
console.log("VoiceOS Website Download & Metadata Integrity Check");
console.log("=================================================");

// 1. Check latest.json existence
if (!fs.existsSync(LATEST_JSON_PATH)) {
  console.error("❌ FAILED: latest.json does not exist at " + LATEST_JSON_PATH);
  process.exit(1);
}

const metadata = JSON.parse(fs.readFileSync(LATEST_JSON_PATH, 'utf8'));
console.log("✓ Found latest.json:", JSON.stringify(metadata, null, 2));

// 2. Validate fields
const requiredFields = ['appName', 'version', 'buildNumber', 'fileName', 'fileSizeBytes', 'sha256', 'minMacOSVersion', 'downloadUrl'];
for (const field of requiredFields) {
  if (!metadata[field]) {
    console.error(`❌ FAILED: Missing required field "${field}" in latest.json`);
    process.exit(1);
  }
}

// 3. Check target DMG file
const dmgPath = path.join(WEBSITE_DIR, metadata.downloadUrl);
if (!fs.existsSync(dmgPath)) {
  console.error(`❌ FAILED: Target DMG file does not exist at ${dmgPath}`);
  process.exit(1);
}

const fileStat = fs.statSync(dmgPath);
console.log(`✓ Target DMG exists: ${dmgPath} (${fileStat.size} bytes)`);

if (fileStat.size !== metadata.fileSizeBytes) {
  console.error(`❌ FAILED: Size mismatch! latest.json specifies ${metadata.fileSizeBytes} bytes, but file on disk is ${fileStat.size} bytes`);
  process.exit(1);
}
console.log("✓ File size matches latest.json exactly");

// 4. Verify SHA-256 Checksum
const fileBuffer = fs.readFileSync(dmgPath);
const calculatedHash = crypto.createHash('sha256').update(fileBuffer).digest('hex');
console.log("Calculated SHA-256: " + calculatedHash);
console.log("Metadata   SHA-256: " + metadata.sha256);

if (calculatedHash !== metadata.sha256) {
  console.error("❌ FAILED: SHA-256 checksum mismatch!");
  process.exit(1);
}
console.log("✓ SHA-256 checksum verified and matches latest.json exactly");

// 5. Verify Appcast
if (!fs.existsSync(APPCAST_PATH)) {
  console.error("❌ FAILED: appcast.xml does not exist at " + APPCAST_PATH);
  process.exit(1);
}
const appcastContent = fs.readFileSync(APPCAST_PATH, 'utf8');
if (!appcastContent.includes(metadata.fileName) || !appcastContent.includes(metadata.version)) {
  console.error("❌ FAILED: appcast.xml does not reference latest version/filename");
  process.exit(1);
}
console.log("✓ appcast.xml verified and contains version enclosure");

console.log("=================================================");
console.log("✓ ALL VERIFICATION CHECKS PASSED!");
console.log("=================================================");

