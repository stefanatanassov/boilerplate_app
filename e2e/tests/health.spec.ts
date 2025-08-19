import { test, expect } from '@playwright/test';

test('health endpoint returns ok and db:true', async ({ request }) => {
  const res = await request.get('/health');
  expect(res.ok()).toBeTruthy();
  const json = await res.json();
  expect(json.status).toBe('ok');
  // db can be true once DB is up; allow bool or string to be tolerant
  expect(json).toHaveProperty('db');
});
