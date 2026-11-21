/**
 * A social crawler (Slack, Facebook, iMessage) must receive this link's Open
 * Graph card. A 302 makes the chat app draw the destination page instead.
 * A person's browser still redirects.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import Fastify, { type FastifyInstance } from 'fastify';
import { redirectRoutes } from './redirect.js';

const query = vi.fn();
vi.mock('../lib/database.js', () => ({
  db: {
    query: (...args: unknown[]) => query(...args),
  },
}));

const SLACKBOT = 'Slackbot-LinkExpanding 1.0 (+https://api.slack.com/robots)';
const DESKTOP =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36';

function linkRow() {
  return {
    id: '00000000-0000-0000-0000-0000000000aa',
    short_code: 'YbPh6NKY',
    title: 'Fatak Udaan credit builder',
    description: 'New visitors install the app.',
    og_title: 'diwali discount on udaan',
    og_description: 'Back in stock. Open in the app.',
    og_image_url: 'https://placehold.co/1200x630.png',
    og_type: 'website',
    original_url: 'https://www.fatakpay.com/fatakudaan-credit-builder',
    web_fallback_url: 'https://www.fatakpay.com/fatakudaan-credit-builder',
    ios_app_store_url: null,
    android_app_store_url: null,
    ios_universal_link: null,
    android_app_link: null,
    app_scheme: 'fatakpay',
    deep_link_path: '/fatakudaan-credit-builder',
    launchpad_mode: 'inherit',
    is_active: true,
    warn_at: null,
    owner_suspended_at: null,
    expires_at: null,
    targeting_rules: {},
    template_settings: null,
    org_settings: null,
    utm_parameters: null,
    deep_link_parameters: {},
    append_click_id: false,
  };
}

function mockDb() {
  query.mockReset();
  query.mockImplementation(async (sql: string) => {
    if (/information_schema\.columns/i.test(sql)) {
      return { rows: [{ '?column?': 1 }], rowCount: 1 };
    }
    if (/FROM links l/i.test(sql)) {
      return { rows: [linkRow()], rowCount: 1 };
    }
    return { rows: [], rowCount: 0 };
  });
}

let app: FastifyInstance;

beforeEach(async () => {
  mockDb();
  app = Fastify();
  await app.register(redirectRoutes);
  await app.ready();
});

afterEach(async () => {
  await new Promise((r) => setImmediate(r));
  await app.close();
});

describe('social preview on the short link', () => {
  it('gives Slack the link card instead of a redirect', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/vmyetycg/YbPh6NKY',
      headers: {
        'user-agent': SLACKBOT,
        host: 'veggie-until-wing.ngrok-free.dev',
        'x-forwarded-proto': 'https',
      },
    });

    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toMatch(/text\/html/);
    expect(res.body).toContain('property="og:title" content="diwali discount on udaan"');
    expect(res.body).toContain('property="og:description" content="Back in stock. Open in the app."');
    expect(res.body).toContain('property="og:image" content="https://placehold.co/1200x630.png"');
    expect(res.body).toContain('https://veggie-until-wing.ngrok-free.dev/vmyetycg/YbPh6NKY');
    expect(res.body).not.toContain('http-equiv="refresh"');
  });

  it('still redirects a person', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/vmyetycg/YbPh6NKY',
      headers: { 'user-agent': DESKTOP, host: 'localhost:3001' },
    });

    expect(res.statusCode).toBe(302);
    expect(res.headers.location).toContain('fatakudaan-credit-builder');
  });
});
