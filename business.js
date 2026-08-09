// business.js
// Everything related to creating and reading business records.
// Business creation goes through the create_business() Postgres RPC —
// never through direct table inserts — so it's atomic (see
// /sql/phase1_migration.sql, section 4).

import { supabase } from './supabase-client.js';

/**
 * Creates a new business, its owner membership, and its settings row,
 * all in a single database transaction via the create_business() RPC.
 * @returns {Promise<{businessId: string|null, error: Error|null}>}
 */
export async function createBusiness({ name, businessType, country, defaultCurrency, timezone }) {
  const { data, error } = await supabase.rpc('create_business', {
    p_name: name,
    p_business_type: businessType,
    p_country: country || null,
    p_default_currency: defaultCurrency || 'NGN',
    p_timezone: timezone || 'Africa/Lagos',
  });

  if (error) {
    return { businessId: null, error };
  }
  return { businessId: data, error: null };
}

/**
 * Returns every active business_members row for the current user, joined
 * with the business's basic info. RLS ensures this only ever returns rows
 * the caller is actually a member of.
 * @returns {Promise<{memberships: Array, error: Error|null}>}
 */
export async function getMyActiveMemberships() {
  const { data, error } = await supabase
    .from('business_members')
    .select('id, role, status, business_id, businesses ( id, name, business_type )')
    .eq('status', 'active');

  return { memberships: data || [], error };
}

/**
 * @returns {Promise<{business: object|null, error: Error|null}>}
 */
export async function getBusiness(businessId) {
  const { data, error } = await supabase
    .from('businesses')
    .select('id, name, business_type, owner_id, created_at')
    .eq('id', businessId)
    .single();

  return { business: data || null, error };
}

/**
 * @returns {Promise<{settings: object|null, error: Error|null}>}
 */
export async function getBusinessSettings(businessId) {
  const { data, error } = await supabase
    .from('business_settings')
    .select('*')
    .eq('business_id', businessId)
    .single();

  return { settings: data || null, error };
}

/**
 * Returns the current user's role within a specific business, or null
 * if they have no active membership there.
 * @returns {Promise<string|null>}
 */
export async function getMyRoleInBusiness(businessId) {
  const { data, error } = await supabase
    .from('business_members')
    .select('role')
    .eq('business_id', businessId)
    .eq('status', 'active')
    .maybeSingle();

  if (error || !data) return null;
  return data.role;
}
