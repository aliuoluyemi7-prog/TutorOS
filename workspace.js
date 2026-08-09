// workspace.js
// Decides which business ("workspace") the current session is operating
// in, and never silently guesses when there's more than one option.
//
// Storage: sessionStorage, not localStorage — scoped to this tab, cleared
// on logout (see auth.js signOut()), so a stale selection can't leak
// across accounts in the same browser.

import { getMyActiveMemberships } from './business.js';

const STORAGE_KEY = 'tutoros_current_business_id';

export function getCurrentBusinessId() {
  return sessionStorage.getItem(STORAGE_KEY);
}

export function setCurrentBusinessId(businessId) {
  sessionStorage.setItem(STORAGE_KEY, businessId);
}

export function clearCurrentBusinessId() {
  sessionStorage.removeItem(STORAGE_KEY);
}

/**
 * Core workspace-resolution logic. Called right after login, and again
 * on direct load of any /app/* page (covers refresh / deep-link cases
 * where sessionStorage might not yet hold a business_id).
 *
 * Returns a destination the caller should redirect to, rather than
 * redirecting itself — keeps this module testable and side-effect-free.
 *
 * @returns {Promise<
 *   { action: 'onboarding' } |
 *   { action: 'choose-workspace', memberships: Array } |
 *   { action: 'enter', businessId: string }
 * >}
 */
export async function resolveWorkspace() {
  // If a workspace is already selected for this tab, trust it — but only
  // if it's still a business the memberships list actually contains.
  // (Handles the case where access was revoked mid-session.)
  const { memberships, error } = await getMyActiveMemberships();

  if (error) {
    throw error;
  }

  if (memberships.length === 0) {
    clearCurrentBusinessId();
    return { action: 'onboarding' };
  }

  const stored = getCurrentBusinessId();
  const storedStillValid = stored && memberships.some((m) => m.business_id === stored);

  if (storedStillValid) {
    return { action: 'enter', businessId: stored };
  }

  if (memberships.length === 1) {
    setCurrentBusinessId(memberships[0].business_id);
    return { action: 'enter', businessId: memberships[0].business_id };
  }

  // 2+ active memberships and no valid stored selection — never guess.
  return { action: 'choose-workspace', memberships };
}
