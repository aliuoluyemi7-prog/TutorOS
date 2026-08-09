// supabase-client.js
// Single Supabase client instance, imported by every other module.
//
// CONFIGURATION REQUIRED:
// Replace SUPABASE_URL and SUPABASE_ANON_KEY below with the values from
// your Supabase project (Project Settings → API).
// The anon key is safe to expose in frontend code — it has no power on
// its own; every table is protected by Row Level Security (see
// /sql/phase1_migration.sql). Never put a service-role key here or
// anywhere in frontend code.

import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const SUPABASE_URL = 'https://mdxkivcyoboqqwpbteif.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1keGtpdmN5b2JvcXF3cGJ0ZWlmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYyMDYyNDQsImV4cCI6MjEwMTc4MjI0NH0.FZfLQNqd7Pt0oDsyDFws7P1gs1uJNmriJUhpJJWKFzo';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true, // needed for email verification / password reset links
  },
});
