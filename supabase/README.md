# SumanTV — Backend (Supabase) guide

Stack: **static HTML + `@supabase/supabase-js`**. No server to run — the browser talks to Supabase directly, protected by Row Level Security.

## 1. Set up
1. Create a project at supabase.com.
2. SQL Editor → paste **`schema.sql`** → Run. (Creates all tables, RLS, and seeds the 4 categories.)
3. Add the client to any page:

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<script>
  const db = supabase.createClient(
    'https://YOUR-PROJECT.supabase.co',
    'YOUR-ANON-PUBLIC-KEY'           // safe to ship — RLS guards every table
  );
</script>
```

## 2. Auto-importing the thumbnail (the "take it from YouTube" bit)
You only store the **video id**; the image URL is derived — no upload needed.

- **YouTube Shorts:** the id is the part after `/shorts/` (or `?v=`).
  `thumbnail_url = https://img.youtube.com/vi/<video_id>/maxresdefault.jpg`
  (fall back to `hqdefault.jpg` if maxres 404s.)
- **Instagram Reels:** no public image URL. Use the **oEmbed / Graph API** once
  (`/instagram_oembed?url=<reel_url>`) and save the returned `thumbnail_url`.
  Do this in a Supabase **Edge Function** so the token stays server-side.

Tip: a `before insert` trigger can auto-fill `thumbnail_url` for YouTube rows from `video_id`.

## 3. How the prototype maps to the tables
| UI on screen                         | Table(s) |
|--------------------------------------|----------|
| Category pills / sections            | `categories` |
| Every reel card / article            | `articles` (+ `article_tags`, `tags`) |
| Home "Featured" / "Viral"            | `articles.is_featured` / `is_viral` |
| Community pages                      | `communities`, `community_members` |
| Events (webinar/meetup/training/talk)| `events`, `event_registrations` |
| Ad slots                             | `ad_slots` (by `placement`) |
| Login / Join buttons                 | Supabase Auth + `profiles` |

## 4. Example reads (drop-in for the live site)

```js
// Home — featured reels
const { data: featured } = await db
  .from('articles')
  .select('*, categories(slug,name_en,name_te,color)')
  .eq('is_featured', true)
  .order('published_at', { ascending: false });

// Category page
const { data: reels } = await db
  .from('articles')
  .select('*, categories!inner(slug)')
  .eq('categories.slug', 'health');

// Join a community  (RLS checks auth.uid() automatically)
await db.from('community_members').insert({ community_id, user_id: user.id });

// Register for an event
await db.from('event_registrations').insert({ event_id, user_id: user.id });

// An ad for a placement
const { data: ad } = await db
  .from('ad_slots')
  .select('*').eq('placement', 'leaderboard').eq('is_active', true)
  .limit(1).single();
```

## 5. Auth (the "Join the community" CTA)
Use Supabase Auth (email magic-link or Google). On first sign-in, upsert a `profiles`
row. The Join / Register buttons in the prototype then become the two `insert` calls above.

## 6. Suggested build order
1. Run `schema.sql`, seed a handful of `articles` by hand.
2. Wire the **home** + **category** pages to read from `articles`.
3. Add Auth → make **Join community** and **Register** write rows.
4. Build a tiny **admin form** (or just the Supabase Table Editor) to add reels by
   pasting a YouTube/Instagram URL.
5. Move Instagram thumbnail fetching into an Edge Function.
