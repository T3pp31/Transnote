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

test('findDmgAsset matches versioned dmg even when decoys come first', function () {
  const assets = [
    { name: 'notes.txt', browser_download_url: 'https://github.com/T3pp31/Transnote/releases/download/v0.2.0/notes.txt' },
    { name: 'Transnote.dmg', browser_download_url: 'https://github.com/T3pp31/Transnote/releases/download/v0.2.0/Transnote.dmg' },
    { name: 'Transnote-0.2.0.dmg.sha256', browser_download_url: 'https://github.com/T3pp31/Transnote/releases/download/v0.2.0/Transnote-0.2.0.dmg.sha256' },
    { name: 'Transnote-0.2.0.dmg', browser_download_url: 'https://github.com/T3pp31/Transnote/releases/download/v0.2.0/Transnote-0.2.0.dmg' },
    { name: 'Transnote-0.2.0-beta.dmg', browser_download_url: 'https://github.com/T3pp31/Transnote/releases/download/v0.2.0/Transnote-0.2.0-beta.dmg' }
  ];
  const matched = app.findDmgAsset(assets);
  assert.strictEqual(matched.name, 'Transnote-0.2.0.dmg');
  assert.strictEqual(
    matched.browser_download_url,
    'https://github.com/T3pp31/Transnote/releases/download/v0.2.0/Transnote-0.2.0.dmg'
  );
  assert.strictEqual(app.findDmgAsset([{ name: 'notes.txt' }, { name: 'Transnote.dmg' }]), undefined);
  assert.strictEqual(app.findDmgAsset([]), undefined);
  assert.strictEqual(app.findDmgAsset(null), undefined);
});

test('findSha256Asset matches expected name even when decoys come first', function () {
  const dmg = { name: 'Transnote-0.2.0.dmg' };
  const assets = [
    { name: 'other.txt', browser_download_url: 'https://github.com/T3pp31/Transnote/releases/download/v0.2.0/other.txt' },
    { name: 'Transnote-0.1.0.dmg.sha256', browser_download_url: 'https://github.com/T3pp31/Transnote/releases/download/v0.2.0/Transnote-0.1.0.dmg.sha256' },
    { name: 'Transnote.dmg.sha256', browser_download_url: 'https://github.com/T3pp31/Transnote/releases/download/v0.2.0/Transnote.dmg.sha256' },
    { name: 'Transnote-0.2.0.dmg.sha256', browser_download_url: 'https://github.com/T3pp31/Transnote/releases/download/v0.2.0/Transnote-0.2.0.dmg.sha256' }
  ];
  const matched = app.findSha256Asset(assets, dmg);
  assert.strictEqual(matched.name, 'Transnote-0.2.0.dmg.sha256');
  assert.strictEqual(
    matched.browser_download_url,
    'https://github.com/T3pp31/Transnote/releases/download/v0.2.0/Transnote-0.2.0.dmg.sha256'
  );
  assert.strictEqual(app.findSha256Asset([{ name: 'Transnote-0.1.0.dmg.sha256' }], dmg), undefined);
  assert.strictEqual(app.findSha256Asset(assets, null), null);
});

const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync(require.resolve('./app.js'), 'utf8');
const config = require('../Config/github-config.json');
// フォールバックURLは distribution.plist の AppName から app.js に生成される。
// 生成ブロックの書式は scripts/generate-site-config.py の render_block を正とする。
const generatedFallbackMatch = source.match(/var fallbackDownloadURL =\s*("([^"]*)")/);
assert.ok(generatedFallbackMatch, 'app.js に生成された fallbackDownloadURL がありません');
const generatedFallbackURL = generatedFallbackMatch[2];

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
      dmgAssetName: 'Transnote.dmg',
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
  assert.strictEqual(site.button.href, generatedFallbackURL);
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

function createObservableElement(tagName) {
  return {
    tagName: tagName || 'div',
    className: '',
    textContent: '',
    href: '',
    attributes: {},
    children: [],
    get firstChild() {
      return this.children.length > 0 ? this.children[0] : null;
    },
    appendChild: function (child) {
      this.children.push(child);
      return child;
    },
    removeChild: function (child) {
      const index = this.children.indexOf(child);
      if (index !== -1) {
        this.children.splice(index, 1);
      }
      return child;
    },
    setAttribute: function (name, value) {
      this.attributes[name] = value;
    }
  };
}

function createDeferred() {
  let resolve;
  let reject;
  const promise = new Promise(function (res, rej) {
    resolve = res;
    reject = rej;
  });
  return { promise: promise, resolve: resolve, reject: reject };
}

function collectNodes(root, predicate, out) {
  const results = out || [];
  if (predicate(root)) {
    results.push(root);
  }
  for (const child of root.children || []) {
    collectNodes(child, predicate, results);
  }
  return results;
}

async function runSiteWithFetchOrder(order, latestPayload, listPayload) {
  const button = createObservableElement('a');
  const version = createObservableElement('span');
  const releaseList = createObservableElement('ul');
  const note = createObservableElement('p');
  const latestDeferred = createDeferred();
  const listDeferred = createDeferred();

  vm.runInNewContext(source, {
    URL: URL,
    document: {
      getElementById: function (id) {
        if (id === 'download-button') { return button; }
        if (id === 'latest-version') { return version; }
        if (id === 'release-list') { return releaseList; }
        return createObservableElement('div');
      },
      querySelector: function () { return note; },
      createElement: function (tag) { return createObservableElement(tag); },
      createTextNode: function (text) { return { textContent: text, children: [] }; }
    },
    fetch: function (url) {
      if (url.endsWith('/latest')) {
        return latestDeferred.promise;
      }
      return listDeferred.promise;
    }
  });

  function resolveLatest() {
    latestDeferred.resolve({ json: function () { return Promise.resolve(latestPayload); } });
  }
  function resolveList() {
    listDeferred.resolve({ json: function () { return Promise.resolve(listPayload); } });
  }

  if (order === 'list-first') {
    resolveList();
    await new Promise(function (resolve) { setImmediate(resolve); });
    resolveLatest();
  } else {
    resolveLatest();
    await new Promise(function (resolve) { setImmediate(resolve); });
    resolveList();
  }
  await new Promise(function (resolve) { setImmediate(resolve); });
  return { button: button, version: version, releaseList: releaseList, note: note };
}

test('renderReleaseList produces identical DOM regardless of fetch resolution order', async function () {
  const latestRelease = {
    tag_name: 'v0.2.0',
    html_url: 'https://github.com/T3pp31/Transnote/releases/tag/v0.2.0',
    assets: [
      {
        name: 'Transnote.dmg',
        browser_download_url: 'https://github.com/T3pp31/Transnote/releases/download/v0.2.0/Transnote.dmg'
      }
    ]
  };
  const releasesList = [
    {
      tag_name: 'v0.2.0',
      prerelease: false,
      published_at: '2026-02-01T00:00:00Z',
      html_url: 'https://github.com/T3pp31/Transnote/releases/tag/v0.2.0',
      assets: [
        { name: 'notes.txt', browser_download_url: 'https://github.com/T3pp31/Transnote/releases/download/v0.2.0/notes.txt' },
        { name: 'Transnote-0.2.0.dmg', browser_download_url: 'https://github.com/T3pp31/Transnote/releases/download/v0.2.0/Transnote-0.2.0.dmg' },
        { name: 'Transnote-0.2.0.dmg.sha256', browser_download_url: 'https://github.com/T3pp31/Transnote/releases/download/v0.2.0/Transnote-0.2.0.dmg.sha256' }
      ]
    },
    {
      tag_name: 'v0.1.9-beta',
      prerelease: true,
      published_at: '2026-01-15T00:00:00Z',
      html_url: 'https://github.com/T3pp31/Transnote/releases/tag/v0.1.9-beta',
      assets: [
        { name: 'Transnote-0.1.9.dmg', browser_download_url: 'https://github.com/T3pp31/Transnote/releases/download/v0.1.9-beta/Transnote-0.1.9.dmg' }
      ]
    }
  ];

  for (const order of ['latest-first', 'list-first']) {
    const result = await runSiteWithFetchOrder(order, latestRelease, releasesList);
    assert.strictEqual(result.releaseList.children.length, 2, order + ': expected 2 rendered items');
    assert.strictEqual(result.note.textContent, 'すべてのリリースの DMG をダウンロードできます。');

    const firstItem = result.releaseList.children[0];
    const firstBadges = collectNodes(firstItem, function (n) { return n.className === 'badge'; }).map(function (n) { return n.textContent; });
    assert.deepStrictEqual(firstBadges, ['最新'], order + ': latest badge must appear on v0.2.0');

    const firstDmgLink = collectNodes(firstItem, function (n) { return n.className === 'release-download'; })[0];
    assert.strictEqual(firstDmgLink.textContent, 'Transnote-0.2.0.dmg');
    assert.strictEqual(firstDmgLink.href, 'https://github.com/T3pp31/Transnote/releases/download/v0.2.0/Transnote-0.2.0.dmg');

    const firstShaLink = collectNodes(firstItem, function (n) { return n.className === 'release-sha'; })[0];
    assert.strictEqual(firstShaLink.textContent, 'SHA256');
    assert.strictEqual(firstShaLink.href, 'https://github.com/T3pp31/Transnote/releases/download/v0.2.0/Transnote-0.2.0.dmg.sha256');

    const secondItem = result.releaseList.children[1];
    const secondBadges = collectNodes(secondItem, function (n) { return n.className === 'badge'; }).map(function (n) { return n.textContent; });
    assert.deepStrictEqual(secondBadges, ['β'], order + ': beta badge without latest badge');
    assert.strictEqual(collectNodes(secondItem, function (n) { return n.className === 'release-sha'; }).length, 0);
  }
});
