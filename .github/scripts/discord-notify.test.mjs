import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildDiscordPayload,
  buildNotification,
  discordWebhookUrl,
  escapeDiscordMarkdown,
  extractReleaseHighlights,
  sendDiscordNotification,
  truncate,
} from './discord-notify.mjs';

const repository = { full_name: 'owner/Alcove' };
const sender = { login: 'developer' };

function response(status, { retryAfter, body } = {}) {
  return {
    ok: status >= 200 && status < 300,
    status,
    headers: { get: (name) => (name === 'Retry-After' ? retryAfter ?? null : null) },
    json: async () => body ?? {},
  };
}

test('normalizes and escapes untrusted Discord markdown', () => {
  assert.equal(truncate('line one\nline two', 30), 'line one line two');
  assert.equal(truncate('A'.repeat(10), 5), 'AAAA…');
  assert.equal(escapeDiscordMarkdown('@everyone **[unsafe](text)**'), '@everyone \\*\\*\\[unsafe\\]\\(text\\)\\*\\*');
});

test('builds push and merged pull request notifications', () => {
  const sha = 'a'.repeat(40);
  const push = buildNotification('push', {
    repository,
    sender,
    ref: 'refs/heads/main',
    after: sha,
    size: 2,
    commits: [{ id: sha }, { id: 'b'.repeat(40) }],
    head_commit: { message: 'feat: release' },
  });
  assert.equal(push.title, 'Alcove 代码已推送');
  assert.match(push.details[3], /提交：2 个/);

  const pullRequest = buildNotification('pull_request_target', {
    repository,
    sender,
    action: 'closed',
    pull_request: { number: 7, title: 'Ship', state: 'closed', merged: true },
  });
  assert.equal(pullRequest.title, 'Alcove PR 已合并');
  assert.equal(pullRequest.color, 'green');
});

test('derives the product name from the repository', () => {
  const notification = buildNotification('issues', {
    repository: { full_name: 'owner/Alcove-Preview' },
    sender,
    action: 'opened',
    issue: { number: 2, title: 'Issue' },
  });
  assert.equal(notification.title, 'Alcove-Preview Issue 已创建');
  assert.equal(notification.username, 'Alcove-Preview');
});

test('normalizes every configured collaboration event', () => {
  const cases = [
    ['issues', { repository, sender, action: 'opened', issue: { number: 2, title: 'Issue' } }],
    ['issue_comment', {
      repository,
      sender,
      issue: { number: 2, title: 'Issue' },
      comment: { body: 'Comment' },
    }],
    ['pull_request_review', {
      repository,
      sender,
      pull_request: { number: 3, title: 'PR' },
      review: { state: 'approved' },
    }],
  ];

  for (const [eventName, event] of cases) {
    const notification = buildNotification(eventName, event);
    assert.match(notification.title, /^Alcove /);
    assert.ok(notification.button.url);
  }
});

test('suppresses successful feature CI and successful release workflow runs', () => {
  assert.equal(buildNotification('workflow_run', {
    repository,
    workflow_run: { name: 'CI', conclusion: 'success', event: 'push', head_branch: 'feature' },
  }), null);
  assert.equal(buildNotification('workflow_run', {
    repository,
    workflow_run: { name: 'Release', conclusion: 'success', event: 'workflow_run', head_branch: 'main' },
  }), null);
});

test('reports main CI success and release workflow failure', () => {
  const mainCI = buildNotification('workflow_run', {
    repository,
    workflow_run: { name: 'CI', conclusion: 'success', event: 'push', head_branch: 'main' },
  });
  assert.equal(mainCI.color, 'green');

  const releaseFailure = buildNotification('workflow_run', {
    repository,
    workflow_run: { name: 'Release', conclusion: 'failure', head_branch: 'main' },
  });
  assert.equal(releaseFailure.color, 'red');
  assert.equal(buildDiscordPayload(releaseFailure).embeds[0].color, 0xED4245);
});

test('reports CI request and suppresses Release planning request', () => {
  const sha = 'a'.repeat(40);
  const ciRequested = buildNotification('workflow_run', {
    repository,
    action: 'requested',
    workflow_run: {
      name: 'CI',
      event: 'pull_request',
      head_branch: 'feature',
      head_sha: sha,
      run_number: 12,
      html_url: 'https://github.com/owner/Alcove/actions/runs/12',
    },
  });
  assert.equal(ciRequested.title, 'Alcove CI 已触发');
  assert.equal(ciRequested.color, 'blue');
  assert.ok(ciRequested.details.includes('提交：aaaaaaa'));

  assert.equal(buildNotification('workflow_run', {
    repository,
    action: 'requested',
    workflow_run: { name: 'Release', head_branch: 'main' },
  }), null);
});

test('extracts at most three release highlights', () => {
  assert.deepEqual(extractReleaseHighlights('- One\n- Two\nText\n* Three\n- Four'), [
    '• One',
    '• Two',
    '• Three',
  ]);
});

test('builds an arm64 release embed with safe action links', () => {
  const notification = buildNotification('release', {
    repository,
    sender,
    release: {
      tag_name: 'v0.2.0-beta.1',
      prerelease: true,
      html_url: 'https://github.com/owner/Alcove/releases/tag/v0.2.0-beta.1',
      body: '- Added automation.',
      assets: [{
        name: 'Alcove.0.2.0-beta.1.dmg',
        browser_download_url: 'https://github.com/owner/Alcove/releases/download/v0.2.0-beta.1/Alcove.0.2.0-beta.1.dmg',
      }],
    },
  });
  const payload = buildDiscordPayload(notification);
  assert.equal(payload.username, 'Alcove');
  assert.deepEqual(payload.allowed_mentions, { parse: [] });
  assert.equal(payload.embeds.length, 1);
  assert.equal(payload.embeds[0].color, 0x57F287);
  assert.equal(payload.embeds[0].url, 'https://github.com/owner/Alcove/releases/tag/v0.2.0-beta.1');
  assert.match(payload.embeds[0].description, /\[查看版本\]\(https:\/\/github\.com\/owner\/Alcove\/releases\/tag\/v0\.2\.0-beta\.1\)/);
  assert.match(payload.embeds[0].description, /\[下载 DMG\]/);
  assert.ok(notification.details.includes('架构：arm64'));
});

test('builds a packaging-started dispatch notification', () => {
  const notification = buildNotification('repository_dispatch', {
    repository,
    sender,
    action: 'release_started',
    client_payload: {
      version: '0.2.0-beta.1',
      prerelease: true,
      dmg_name: 'Alcove.0.2.0-beta.1.dmg',
      sha: 'a'.repeat(40),
      run_url: 'https://github.com/owner/Alcove/actions/runs/12',
    },
  });
  assert.equal(notification.title, 'Alcove 0.2.0-beta.1 开始打包');
  assert.equal(notification.color, 'blue');
  assert.ok(notification.details.includes('架构：arm64'));
  assert.ok(notification.details.includes('提交：aaaaaaa'));
  assert.equal(notification.button.url, 'https://github.com/owner/Alcove/actions/runs/12');
});

test('escapes markdown, prevents mentions, and rejects untrusted action URLs', () => {
  const notification = buildNotification('issue_comment', {
    repository,
    sender,
    issue: { number: 2, title: '[unsafe](title)' },
    comment: { body: '@everyone **[unsafe](comment)**', html_url: 'https://example.com/steal' },
  });
  const payload = buildDiscordPayload(notification);
  assert.deepEqual(payload.allowed_mentions, { parse: [] });
  assert.match(payload.embeds[0].description, /\\\[unsafe\\\]\\\(title\\\)/);
  assert.match(payload.embeds[0].description, /@everyone \\\*\\\*\\\[unsafe\\\]\\\(comment\\\)\\\*\\\*/);
  assert.equal(payload.embeds[0].url, 'https://github.com/owner/Alcove');
});

test('preserves webhook parameters, enables wait, and accepts every 2xx response', async () => {
  let request;
  await sendDiscordNotification({ content: 'test' }, 'https://discord.com/api/webhooks/id/token?thread_id=42', {
    fetchImplementation: async (url, options) => {
      request = { url, options };
      return response(204);
    },
  });
  const webhookUrl = new URL(request.url);
  assert.equal(webhookUrl.searchParams.get('thread_id'), '42');
  assert.equal(webhookUrl.searchParams.get('wait'), 'true');
  assert.equal(request.options.method, 'POST');

  await sendDiscordNotification({}, 'https://discord.com/api/webhooks/id/token', {
    fetchImplementation: async () => response(201),
  });
  assert.equal(discordWebhookUrl('https://discord.com/api/webhooks/id/token?wait=false'), 'https://discord.com/api/webhooks/id/token?wait=true');
});

test('uses Discord rate-limit delays before retrying', async () => {
  const waits = [];
  let attempts = 0;
  await sendDiscordNotification({}, 'https://discord.com/api/webhooks/id/token', {
    fetchImplementation: async () => {
      attempts += 1;
      return attempts === 1 ? response(429, { retryAfter: '1.5' }) : response(204);
    },
    wait: async (milliseconds) => waits.push(milliseconds),
  });
  assert.equal(attempts, 2);
  assert.deepEqual(waits, [1_500]);
});

test('uses retry_after JSON when Discord omits Retry-After', async () => {
  const waits = [];
  let attempts = 0;
  await sendDiscordNotification({}, 'https://discord.com/api/webhooks/id/token', {
    fetchImplementation: async () => {
      attempts += 1;
      return attempts === 1 ? response(429, { body: { retry_after: 0.25 } }) : response(204);
    },
    wait: async (milliseconds) => waits.push(milliseconds),
  });
  assert.equal(attempts, 2);
  assert.deepEqual(waits, [250]);
});

test('retries network and 5xx failures but not other 4xx responses', async () => {
  const waits = [];
  let attempts = 0;
  await sendDiscordNotification({}, 'https://discord.com/api/webhooks/id/token', {
    fetchImplementation: async () => {
      attempts += 1;
      if (attempts === 1) throw new Error('network');
      return attempts === 2 ? response(503) : response(204);
    },
    wait: async (milliseconds) => waits.push(milliseconds),
  });
  assert.equal(attempts, 3);
  assert.deepEqual(waits, [250, 500]);

  attempts = 0;
  await assert.rejects(sendDiscordNotification({}, 'https://discord.com/api/webhooks/id/token', {
    fetchImplementation: async () => {
      attempts += 1;
      return response(401);
    },
    wait: async () => {},
  }));
  assert.equal(attempts, 1);
});

test('rejects an invalid webhook URL without echoing its value', async () => {
  const invalidWebhook = 'not-a-url-with-secret-token';
  await assert.rejects(
    sendDiscordNotification({}, invalidWebhook),
    (error) => error.message === 'DISCORD_WEBHOOK_URL is invalid.' && !error.message.includes(invalidWebhook),
  );
});
