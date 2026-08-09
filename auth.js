// auth.js
// All Supabase Auth calls live here so every page uses the same logic.

import { supabase } from './supabase-client.js';

/**
 * Creates a new user account. A `profiles` row is created automatically
 * by the handle_new_user() database trigger — no client-side insert needed.
 * @returns {Promise<{data, error}>}
 */
export async function signUp({ fullName, email, password }) {
  return await supabase.auth.signUp({
    email,
    password,
    options: {
      data: { full_name: fullName },
      emailRedirectTo: `${window.location.origin}/verify-email.html`,
    },
  });
}

/**
 * @returns {Promise<{data, error}>}
 */
export async function signIn({ email, password }) {
  return await supabase.auth.signInWithPassword({ email, password });
}

/**
 * Signs the user out and clears the locally-stored workspace selection
 * (see workspace.js) so the next login can't accidentally reuse a stale
 * business_id from a different account in the same browser tab.
 */
export async function signOut() {
  sessionStorage.removeItem('tutoros_current_business_id');
  return await supabase.auth.signOut();
}

/**
 * @returns {Promise<{data: {session}, error}>}
 */
export async function getSession() {
  return await supabase.auth.getSession();
}

/**
 * Sends a password-reset email with a link back to reset-password.html.
 * @returns {Promise<{data, error}>}
 */
export async function requestPasswordReset(email) {
  return await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${window.location.origin}/reset-password.html`,
  });
}

/**
 * Called on the reset-password page after the user follows the emailed
 * link (Supabase will have already placed a recovery session in the URL).
 * @returns {Promise<{data, error}>}
 */
export async function updatePassword(newPassword) {
  return await supabase.auth.updateUser({ password: newPassword });
}

/**
 * Convenience: is there a logged-in user right now?
 * @returns {Promise<boolean>}
 */
export async function isAuthenticated() {
  const { data } = await getSession();
  return !!data.session;
}
