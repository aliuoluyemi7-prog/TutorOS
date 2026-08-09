// router-guard.js
// Import this as the FIRST script on every protected page (dashboard,
// business-setup, choose-workspace). It is a UX convenience only — it
// stops a logged-out user from seeing a flash of a protected page before
// being redirected. It is NOT the security boundary; Row Level Security
// on every table is what actually prevents unauthorized data access even
// if this check were bypassed entirely (e.g. by editing requests directly).

import { getSession } from './auth.js';

export async function requireAuth() {
  const { data, error } = await getSession();
  if (error || !data.session) {
    window.location.replace('login.html');
    return null;
  }
  return data.session;
}
