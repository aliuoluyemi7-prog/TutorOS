// ui-helpers.js
// Small, dependency-free UI utilities shared across pages.

/**
 * Shows a temporary toast message. Expects a <div id="toast"></div>
 * to exist somewhere in the page (present in every Phase 1 page).
 */
export function showToast(message, type = 'info') {
  let toast = document.getElementById('toast');
  if (!toast) {
    toast = document.createElement('div');
    toast.id = 'toast';
    document.body.appendChild(toast);
  }
  toast.textContent = message;
  toast.className = `toast toast--${type} toast--visible`;
  clearTimeout(toast._hideTimer);
  toast._hideTimer = setTimeout(() => {
    toast.className = 'toast';
  }, 4000);
}

/**
 * Disables a form's submit button and shows a loading label while an
 * async action runs, then restores it. Prevents double-submits.
 */
export async function withLoading(buttonEl, loadingLabel, action) {
  const originalLabel = buttonEl.textContent;
  const originalDisabled = buttonEl.disabled;
  buttonEl.disabled = true;
  buttonEl.textContent = loadingLabel;
  try {
    return await action();
  } finally {
    buttonEl.disabled = originalDisabled;
    buttonEl.textContent = originalLabel;
  }
}

export function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(email).trim());
}

export function isNonEmpty(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

/**
 * Renders a friendly message for common Supabase auth/RLS error shapes,
 * falling back to the raw message for anything unrecognized.
 */
export function friendlyError(error) {
  if (!error) return 'Something went wrong. Please try again.';
  const msg = error.message || String(error);
  if (msg.toLowerCase().includes('invalid login credentials')) {
    return 'Incorrect email or password.';
  }
  if (msg.toLowerCase().includes('user already registered')) {
    return 'An account with this email already exists.';
  }
  if (msg.toLowerCase().includes('email not confirmed')) {
    return 'Please verify your email before logging in.';
  }
  return msg;
}
