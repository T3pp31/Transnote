// Node テスト用に最小限の DOM / fetch スタブを用意する。
process.env.TZ = 'UTC';

function noopElement() {
  return {
    className: '',
    textContent: '',
    href: '',
    appendChild: function () {},
    removeChild: function () {},
    setAttribute: function () {},
    firstChild: null
  };
}

global.document = {
  getElementById: function () { return noopElement(); },
  querySelector: function () { return noopElement(); },
  createElement: function () { return noopElement(); },
  createTextNode: function (text) { return { textContent: text }; }
};

global.fetch = function () {
  return Promise.resolve({
    ok: true,
    headers: { get: function () { return null; } },
    json: function () { return Promise.resolve([]); }
  });
};

const assert = require('assert');
const app = require('./app.js');

async function test(name, fn) {
  try {
    await fn();
    console.log('PASS: ' + name);
  } catch (error) {
    console.error('FAIL: ' + name + ' - ' + error.message);
    process.exitCode = 1;
  }
}

test('isAllowedDownloadURL allows github.com', function () {
  assert.strictEqual(
    app.isAllowedDownloadURL('https://github.com/T3pp31/Transnote/releases/download/v0.1.0/Transnote.dmg'),
    true
  );
});

test('isAllowedDownloadURL allows current GitHub release asset host', function () {
  assert.strictEqual(
    app.isAllowedDownloadURL('https://release-assets.githubusercontent.com/github-production-release-asset-2e65be/Transnote.dmg'),
    true
  );
});

test('isAllowedDownloadURL rejects http', function () {
  assert.strictEqual(app.isAllowedDownloadURL('http://github.com/x'), false);
});

test('isAllowedDownloadURL rejects other host', function () {
  assert.strictEqual(app.isAllowedDownloadURL('https://evil.example.com/x'), false);
});

test('formatDate formats ISO date', function () {
  assert.strictEqual(app.formatDate('2026-01-15T00:00:00Z'), '2026年1月15日');
});

test('findDmgAsset matches versioned dmg', function () {
  const assets = [
    { name: 'Transnote-0.2.0.dmg' },
    { name: 'notes.txt' }
  ];
  assert.strictEqual(app.findDmgAsset(assets).name, 'Transnote-0.2.0.dmg');
});

test('findSha256Asset matches expected name', function () {
  const dmg = { name: 'Transnote-0.2.0.dmg' };
  const assets = [
    { name: 'Transnote-0.2.0.dmg.sha256' },
    { name: 'other.txt' }
  ];
  assert.strictEqual(app.findSha256Asset(assets, dmg).name, 'Transnote-0.2.0.dmg.sha256');
});

const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync(require.resolve('./app.js'), 'utf8');
const config = require('../Config/github-config.json');

// 別リポジトリ・許可ホストへの設定変更が実際の動作に反映されることを確認する。
const customConfig = {
  expected_repository: 'Example/OtherApp',
  github_api_base: 'https://api.github.com/repos/Example/OtherApp',
  fallback_download_url: 'https://downloads.example.test/Other.dmg',
  allowed_download_hosts: ['downloads.example.test']
};

async function runSite(settings, release, overrideConfig) {
  const button = noopElement();
  button.href = 'initial';
  const version = noopElement();
  const note = noopElement();
  note.children = [];
  note.appendChild = function (child) { this.children.push(child); };
  const requests = [];
  let script = source;
  if (overrideConfig) {
    const variables = {
      fallbackDownloadURL: settings.fallback_download_url,
      expectedRepository: settings.expected_repository,
      allowedDownloadHosts: settings.allowed_download_hosts,
      githubAPIBase: settings.github_api_base
    };
    const block = Object.keys(variables).map(function (name) {
      return 'var ' + name + ' = ' + JSON.stringify(variables[name]) + ';';
    }).join('\n');
    script = script.replace(
      /  \/\/ BEGIN CONFIG[^\n]*\n[\s\S]*?  \/\/ END CONFIG/,
      block
    );
  }
  vm.runInNewContext(script, {
    URL: URL,
    document: {
      getElementById: function (id) {
        if (id === 'download-button') { return button; }
        if (id === 'latest-version') { return version; }
        return noopElement();
      },
      querySelector: function () { return note; },
      createElement: function () { return noopElement(); },
      createTextNode: function (text) { return { textContent: text }; }
    },
    fetch: function (url) {
      requests.push(url);
      return Promise.resolve({
        json: function () {
          return Promise.resolve(url.endsWith('/latest') ? release : []);
        }
      });
    }
  });
  await new Promise(function (resolve) { setImmediate(resolve); });
  return { button: button, version: version, note: note, requests: requests };
}

function releaseFor(settings, downloadURL) {
  return {
    html_url: 'https://github.com/' + settings.expected_repository + '/releases/tag/v1.0.0',
    tag_name: 'v1.0.0',
    assets: downloadURL ? [{ name: 'Transnote.dmg', browser_download_url: downloadURL }] : []
  };
}

test('generated site settings drive API requests and fallback URL', async function () {
  const site = await runSite(config, releaseFor(config));
  assert.deepStrictEqual(site.requests, [
    config.github_api_base + '/releases/latest',
    config.github_api_base + '/releases?per_page=30'
  ]);
  assert.strictEqual(site.button.href, config.fallback_download_url);
  assert.strictEqual(site.version.textContent, '最新版 v1.0.0');
});

test('repository change drives API requests and release-list error link', async function () {
  const site = await runSite(customConfig, releaseFor(customConfig), true);
  assert.deepStrictEqual(site.requests, [
    customConfig.github_api_base + '/releases/latest',
    customConfig.github_api_base + '/releases?per_page=30'
  ]);
  assert.strictEqual(site.button.href, customConfig.fallback_download_url);
  assert.strictEqual(site.version.textContent, '最新版 v1.0.0');
  const link = site.note.children.find(function (child) {
    return child.textContent === 'GitHub Releases';
  });
  assert.strictEqual(link.href, 'https://github.com/Example/OtherApp/releases');
});

test('changed host setting accepts only configured HTTPS downloads', async function () {
  const allowedURL = 'https://downloads.example.test/release.dmg';
  const allowed = await runSite(customConfig, releaseFor(customConfig, allowedURL), true);
  assert.strictEqual(allowed.button.href, allowedURL);
  for (const url of [
    'https://github.com/Example/OtherApp/release.dmg',
    'https://evil.downloads.example.test/release.dmg',
    'http://downloads.example.test/release.dmg'
  ]) {
    const rejected = await runSite(customConfig, releaseFor(customConfig, url), true);
    assert.strictEqual(rejected.button.href, customConfig.fallback_download_url);
  }
});

test('changed repository setting rejects releases from the old repository', async function () {
  const site = await runSite(customConfig, releaseFor(config), true);
  assert.strictEqual(site.button.href, 'initial');
  assert.strictEqual(site.version.textContent, '');
});
