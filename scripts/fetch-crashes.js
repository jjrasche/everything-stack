#!/usr/bin/env node

/**
 * Firebase Crashlytics Crash Fetcher
 *
 * Autonomous crash log querying without Firebase console access.
 *
 * Usage:
 *   node scripts/fetch-crashes.js --platform android
 *   node scripts/fetch-crashes.js --platform ios
 *
 * Output:
 *   JSON array of crashes with: timestamp, appVersion, platform, stackTrace, exceptionMessage
 */

const https = require('https');
const fs = require('fs');
const crypto = require('crypto');
const path = require('path');

// App ID mapping
const APP_IDS = {
  android: '1:695005425106:android:d16559ef358c56db632c0b',
  // TODO: ios: 'TBD - get from Firebase Console',
  // TODO: web: 'TBD - get from Firebase Console'
};

const PROJECT_ID = 'everything-stack-5a842';

// Parse command line arguments
function getPlatform() {
  const args = process.argv.slice(2);
  const platformArg = args.find(arg => arg.startsWith('--platform='));
  const platform = platformArg ? platformArg.split('=')[1] : 'android';

  if (!APP_IDS[platform]) {
    console.error(`❌ Unknown platform: ${platform}`);
    console.error(`Available platforms: ${Object.keys(APP_IDS).join(', ')}`);
    process.exit(1);
  }

  return platform;
}

// Read service account
function getServiceAccount() {
  const keyPath = path.join(__dirname, '..', '.firebase', 'service-account-key.json');
  try {
    return JSON.parse(fs.readFileSync(keyPath, 'utf8'));
  } catch (err) {
    console.error('❌ Service account key not found at:', keyPath);
    process.exit(1);
  }
}

// Create JWT for authentication
function createJWT(serviceAccount) {
  const header = Buffer.from(JSON.stringify({
    alg: 'RS256',
    typ: 'JWT'
  })).toString('base64').replace(/[=+/]/g, m => ({
    '=': '', '+': '-', '/': '_'
  }[m]));

  const now = Math.floor(Date.now() / 1000);
  const payload = Buffer.from(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/cloud-platform',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now
  })).toString('base64').replace(/[=+/]/g, m => ({
    '=': '', '+': '-', '/': '_'
  }[m]));

  const sign = crypto.createSign('RSA-SHA256');
  sign.update(`${header}.${payload}`);
  const sig = sign.sign(serviceAccount.private_key, 'base64')
    .replace(/[=+/]/g, m => ({
      '=': '', '+': '-', '/': '_'
    }[m]));

  return `${header}.${payload}.${sig}`;
}

// Get access token
function getAccessToken(serviceAccount) {
  return new Promise((resolve, reject) => {
    const jwt = createJWT(serviceAccount);
    const postData = JSON.stringify({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt
    });

    const options = {
      hostname: 'oauth2.googleapis.com',
      path: '/token',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': postData.length
      }
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode === 200) {
          const parsed = JSON.parse(data);
          resolve(parsed.access_token);
        } else {
          reject(new Error(`Token error (${res.statusCode}): ${data}`));
        }
      });
    });

    req.on('error', reject);
    req.write(postData);
    req.end();
  });
}

// Generic HTTPS GET request
function httpsGet(hostname, path, token) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname,
      path,
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      }
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode === 200) {
          try {
            resolve(JSON.parse(data));
          } catch (e) {
            reject(new Error(`JSON parse error: ${e.message}`));
          }
        } else if (res.statusCode === 404) {
          resolve(null); // No data found
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${data}`));
        }
      });
    });

    req.on('error', reject);
    req.end();
  });
}

// Filter crashes from today
function isFromToday(timestamp) {
  if (!timestamp) return false;

  const crashDate = new Date(timestamp);
  const today = new Date();

  return crashDate.toDateString() === today.toDateString();
}

// Fetch individual crashes for an issue
async function getCrashesForIssue(token, issueId) {
  const path = `/v1/projects/${PROJECT_ID}/apps/${APP_IDS[getPlatform()]}/issues/${issueId}/crashes`;

  try {
    const data = await httpsGet('firebasecrashlytics.googleapis.com', path, token);
    return data?.crashes || [];
  } catch (err) {
    console.error(`⚠️  Warning: Could not fetch crashes for issue ${issueId}: ${err.message}`);
    return [];
  }
}

// Parse crash data into structured format
function parseRawCrash(issue, crash) {
  return {
    timestamp: crash.crashTime || issue.createTime,
    appVersion: crash.appInfo?.appVersion || 'unknown',
    platform: getPlatform(),
    stackTrace: crash.stackTrace || issue.stackTrace || 'unavailable',
    exceptionMessage: crash.exceptionMessage || issue.exceptionMessage || 'unknown'
  };
}

// Main async function
async function main() {
  try {
    const platform = getPlatform();
    const serviceAccount = getServiceAccount();

    console.error(`📱 Fetching crashes for platform: ${platform}\n`);

    // Step 1: Get access token
    console.error('🔑 Authenticating...');
    const token = await getAccessToken(serviceAccount);
    console.error('✅ Authentication successful\n');

    // Step 2: Get list of issues
    console.error('📋 Querying issues...');
    const issuesPath = `/v1/projects/${PROJECT_ID}/apps/${APP_IDS[platform]}/issues`;
    const issuesData = await httpsGet('firebasecrashlytics.googleapis.com', issuesPath, token);

    if (!issuesData || !issuesData.issues || issuesData.issues.length === 0) {
      console.error('⚠️  No crash issues found\n');
      console.log(JSON.stringify([], null, 2));
      return;
    }

    console.error(`✅ Found ${issuesData.issues.length} issue(s)\n`);

    // Step 3: For each issue, fetch individual crashes
    const allCrashes = [];

    for (const issue of issuesData.issues) {
      console.error(`  Fetching crashes for issue: ${issue.id}`);

      const crashes = await getCrashesForIssue(token, issue.id);

      // Parse and filter crashes from today
      for (const crash of crashes) {
        const parsed = parseRawCrash(issue, crash);
        if (isFromToday(parsed.timestamp)) {
          allCrashes.push(parsed);
        }
      }
    }

    // Sort by timestamp (newest first)
    allCrashes.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));

    console.error(`\n✅ Retrieved ${allCrashes.length} crash(es) from today\n`);

    // Output structured JSON (this is what the automation will parse)
    console.log(JSON.stringify(allCrashes, null, 2));

  } catch (error) {
    console.error(`\n❌ ERROR: ${error.message}`);
    process.exit(1);
  }
}

main();
