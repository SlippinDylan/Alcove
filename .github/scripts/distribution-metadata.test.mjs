import assert from 'node:assert/strict';
import test from 'node:test';

import {
  renderCask,
  updateAppcastDisplayVersion,
  validateCaskAdvance,
} from './distribution-metadata.mjs';

test('renders a pinned beta cask for the immutable GitHub Release DMG', () => {
  const cask = renderCask('0.2.0-beta.1', 'a'.repeat(64));

  assert.match(cask, /^cask "alcove@beta" do/m);
  assert.match(cask, /version "0\.2\.0-beta\.1"/);
  assert.match(cask, /sha256 "a{64}"/);
  assert.match(cask, /auto_updates true/);
  assert.match(cask, /depends_on arch: :arm64/);
  assert.match(cask, /depends_on macos: :tahoe/);
});

test('renders the unversioned cask token for stable releases', () => {
  assert.match(renderCask('1.0.0', 'b'.repeat(64)), /^cask "alcove" do/m);
});

test('keeps alpha releases isolated from the beta Cask', () => {
  assert.match(renderCask('1.0.0-alpha.1', 'c'.repeat(64)), /^cask "alcove@alpha" do/m);
});

test('rejects a malformed DMG digest', () => {
  assert.throws(() => renderCask('1.0.0', 'not-a-digest'));
});

test('allows idempotent and advancing Cask versions but rejects downgrades', () => {
  const current = 'cask "alcove@beta" do\n  version "0.2.0-beta.2"\nend\n';
  assert.doesNotThrow(() => validateCaskAdvance(current, '0.2.0-beta.2'));
  assert.doesNotThrow(() => validateCaskAdvance(current, '0.2.0-beta.3'));
  assert.throws(() => validateCaskAdvance(current, '0.2.0-beta.1'));
});

test('updates only the matching appcast item display version', () => {
  const source = `<?xml version="1.0"?>
<rss><channel>
<item>
  <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
  <enclosure url="https://example.com/Alcove.0.1.0.dmg" />
</item>
<item>
  <sparkle:shortVersionString>0.2.0</sparkle:shortVersionString>
  <enclosure url="https://example.com/Alcove.0.2.0-beta.1.dmg" />
</item>
</channel></rss>`;

  const updated = updateAppcastDisplayVersion(
    source,
    '0.2.0-beta.1',
    'Alcove.0.2.0-beta.1.dmg',
  );

  assert.match(updated, /<sparkle:shortVersionString>0\.1\.0<\/sparkle:shortVersionString>/);
  assert.match(updated, /<sparkle:shortVersionString>0\.2\.0-beta\.1<\/sparkle:shortVersionString>/);
});

test('rejects missing or ambiguous appcast items', () => {
  const item = `<item><sparkle:shortVersionString>1.0.0</sparkle:shortVersionString><enclosure url="Alcove.1.0.0.dmg" /></item>`;
  assert.throws(() => updateAppcastDisplayVersion(item, '1.0.0', 'missing.dmg'));
  assert.throws(() => updateAppcastDisplayVersion(`${item}${item}`, '1.0.0', 'Alcove.1.0.0.dmg'));
});
