/* ============================================================
   SumanTV — Supabase client setup
   ------------------------------------------------------------
   1. Replace SUPABASE_URL and SUPABASE_ANON_KEY below with the
      values from your Supabase project:
        Dashboard → Project Settings → API
      The anon/public key is SAFE to ship in the browser — every
      table is protected by Row Level Security (see schema.sql).
   2. index.html already loads this file AFTER the supabase-js CDN
      script, so `window.supabase` exists here.
   3. While the placeholders are unchanged, the site runs on its
      built-in seed data. Once you fill them in, `SumanTVDB.hydrate()`
      replaces the seed content with live rows.
   ============================================================ */

const SUPABASE_URL = 'https://YOUR-PROJECT.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR-ANON-PUBLIC-KEY';

(function () {
  // Don't initialise until the placeholders are replaced.
  var configured =
    SUPABASE_URL.indexOf('YOUR-PROJECT') === -1 &&
    SUPABASE_ANON_KEY.indexOf('YOUR-ANON') === -1;

  if (!configured || !window.supabase) {
    console.info('[SumanTV] Running on seed data. Add Supabase keys in supabase/client.js to go live.');
    return;
  }

  const db = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

  /* ---------- queries ---------- */
  const api = {
    // Home — featured + viral reels
    featured() {
      return db.from('articles')
        .select('*, categories(slug,name_en,name_te,color)')
        .eq('is_featured', true)
        .order('published_at', { ascending: false });
    },
    viral() {
      return db.from('articles')
        .select('*, categories(slug,name_en,name_te,color)')
        .eq('is_viral', true)
        .order('views', { ascending: false });
    },
    // Category page
    byCategory(slug) {
      return db.from('articles')
        .select('*, categories!inner(slug,name_en,name_te,color)')
        .eq('categories.slug', slug)
        .order('published_at', { ascending: false });
    },
    // Single reel/article
    reel(slug) {
      return db.from('articles')
        .select('*, categories(slug,name_en,name_te,color), article_tags(tags(name))')
        .eq('slug', slug)
        .single();
    },
    // Communities
    communities() {
      return db.from('communities')
        .select('*, categories(slug,color)');
    },
    community(slug) {
      return db.from('communities')
        .select('*, categories(slug,color), events(*)')
        .eq('slug', slug)
        .single();
    },
    // Ads for a placement
    ad(placement) {
      return db.from('ad_slots')
        .select('*').eq('placement', placement).eq('is_active', true)
        .limit(1).maybeSingle();
    },
    // ---- auth-gated writes ----
    joinCommunity(communityId, userId) {
      return db.from('community_members').insert({ community_id: communityId, user_id: userId });
    },
    leaveCommunity(communityId, userId) {
      return db.from('community_members').delete()
        .match({ community_id: communityId, user_id: userId });
    },
    registerForEvent(eventId, userId) {
      return db.from('event_registrations').insert({ event_id: eventId, user_id: userId });
    },
  };

  /* ---------- thumbnail helper (auto-import from YouTube) ----------
     Store only the video_id; derive the image URL. */
  function youtubeThumb(videoId) {
    return 'https://img.youtube.com/vi/' + videoId + '/maxresdefault.jpg';
  }

  /* ---------- optional hydration hook ----------
     index.html calls SumanTVDB.hydrate(route) after each render.
     Fill rows in here to swap seed content for live data. The seed
     UI stays on screen until your data resolves, so there is never
     a blank state. Left intentionally light — wire the pieces you
     ship first (e.g. home + category), then expand. */
  async function hydrate(route) {
    // Example: replace the home "Viral right now" rail with live rows.
    // const { data } = await api.viral();
    // if (data && data.length) renderViralRail(data);   // your DOM update
    // (No-op by default so the static demo keeps working.)
  }

  window.SumanTVDB = { db, api, youtubeThumb, hydrate };
  console.info('[SumanTV] Supabase connected.');
})();
