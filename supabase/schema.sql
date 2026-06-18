-- ============================================================
--  SumanTV — Supabase schema
--  Paste into Supabase → SQL Editor → Run.
--  Maps 1:1 to the HTML prototype (categories, reels/articles,
--  communities, events, ads, members).
-- ============================================================

-- ---------- enums ----------
create type content_source as enum ('youtube', 'instagram');
create type event_kind     as enum ('webinar', 'meetup', 'training', 'expert_talk');
create type ad_placement   as enum ('leaderboard', 'sidebar', 'infeed', 'in_article');

-- ---------- profiles (extends Supabase auth.users) ----------
create table profiles (
  id          uuid primary key references auth.users on delete cascade,
  full_name   text,
  avatar_url  text,
  language    text default 'en',          -- 'en' | 'te'
  created_at  timestamptz default now()
);

-- ---------- categories  (Business / Health / News / Bhakthi) ----------
create table categories (
  id        bigint generated always as identity primary key,
  slug      text unique not null,         -- 'news', 'health', 'business', 'bakthi'
  name_en   text not null,
  name_te   text not null,
  color     text not null,                -- hex used in the UI
  sort      int  default 0
);

-- ---------- articles  (each YouTube Short / Instagram Reel) ----------
create table articles (
  id            bigint generated always as identity primary key,
  slug          text unique not null,
  category_id   bigint not null references categories on delete restrict,
  title_en      text not null,
  title_te      text,
  description_en text,
  description_te text,
  body_en       text,
  body_te       text,
  source        content_source not null,  -- youtube | instagram
  source_url    text not null,            -- full watch/reel URL
  video_id      text,                     -- YouTube/IG id (drives the thumbnail)
  thumbnail_url text,                     -- see auto-import note below
  channel       text,                     -- e.g. 'SumanTV News'
  duration      text,                     -- '0:48'
  views         bigint default 0,
  keywords      text[]  default '{}',     -- SEO keywords (chips on article page)
  is_featured   boolean default false,
  is_viral      boolean default false,
  published_at  timestamptz default now(),
  created_at    timestamptz default now()
);
create index on articles (category_id);
create index on articles (is_featured) where is_featured;
create index on articles (is_viral)    where is_viral;

-- ---------- tags  (the #chips) ----------
create table tags (
  id   bigint generated always as identity primary key,
  name text unique not null
);
create table article_tags (
  article_id bigint references articles on delete cascade,
  tag_id     bigint references tags     on delete cascade,
  primary key (article_id, tag_id)
);

-- ---------- communities  (one per category) ----------
create table communities (
  id            bigint generated always as identity primary key,
  slug          text unique not null,
  category_id   bigint not null references categories on delete restrict,
  name          text not null,
  name_te       text,
  tagline       text,
  cover_url     text,
  perks         text[] default '{}',
  members_count int    default 0,         -- kept fresh by trigger below
  created_at    timestamptz default now()
);

create table community_members (
  community_id bigint references communities on delete cascade,
  user_id      uuid   references profiles    on delete cascade,
  joined_at    timestamptz default now(),
  primary key (community_id, user_id)
);

-- keep members_count in sync
create or replace function bump_members_count() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    update communities set members_count = members_count + 1 where id = new.community_id;
  elsif tg_op = 'DELETE' then
    update communities set members_count = greatest(members_count - 1, 0) where id = old.community_id;
  end if;
  return null;
end $$;
create trigger trg_members_count
  after insert or delete on community_members
  for each row execute function bump_members_count();

-- ---------- events  (webinars / meetups / training / expert talks) ----------
create table events (
  id           bigint generated always as identity primary key,
  community_id bigint not null references communities on delete cascade,
  title        text not null,
  title_te     text,
  kind         event_kind not null,
  starts_at    timestamptz not null,
  mode         text,                      -- 'Online', 'T-Hub', 'KBR Park'…
  host         text,
  created_at   timestamptz default now()
);
create index on events (community_id, starts_at);

create table event_registrations (
  event_id     bigint references events   on delete cascade,
  user_id      uuid   references profiles  on delete cascade,
  registered_at timestamptz default now(),
  primary key (event_id, user_id)
);

-- ---------- ad slots ----------
create table ad_slots (
  id          bigint generated always as identity primary key,
  placement   ad_placement not null,
  headline    text,
  sub         text,
  image_url   text,
  target_url  text,
  category_id bigint references categories on delete set null,  -- null = run everywhere
  weight      int default 1,
  is_active   boolean default true
);

-- ============================================================
--  Row Level Security  (content public, writes require login)
-- ============================================================
alter table profiles            enable row level security;
alter table articles            enable row level security;
alter table categories          enable row level security;
alter table tags                enable row level security;
alter table article_tags        enable row level security;
alter table communities         enable row level security;
alter table community_members   enable row level security;
alter table events              enable row level security;
alter table event_registrations enable row level security;
alter table ad_slots            enable row level security;

-- public, read-only content
create policy "public read" on categories        for select using (true);
create policy "public read" on articles           for select using (true);
create policy "public read" on tags               for select using (true);
create policy "public read" on article_tags       for select using (true);
create policy "public read" on communities        for select using (true);
create policy "public read" on events             for select using (true);
create policy "public read" on ad_slots           for select using (is_active);

-- profiles: a user manages their own row
create policy "own profile read"   on profiles for select using (auth.uid() = id);
create policy "own profile upsert" on profiles for insert with check (auth.uid() = id);
create policy "own profile update" on profiles for update using (auth.uid() = id);

-- community membership: see your own, join/leave yourself
create policy "see own memberships" on community_members for select using (auth.uid() = user_id);
create policy "join community"      on community_members for insert with check (auth.uid() = user_id);
create policy "leave community"     on community_members for delete using (auth.uid() = user_id);

-- event registrations: same pattern
create policy "see own regs"  on event_registrations for select using (auth.uid() = user_id);
create policy "register"      on event_registrations for insert with check (auth.uid() = user_id);
create policy "unregister"    on event_registrations for delete using (auth.uid() = user_id);

-- ============================================================
--  Seed the 4 categories
-- ============================================================
insert into categories (slug, name_en, name_te, color, sort) values
  ('news',     'News',     'వార్తలు',  '#E11D48', 1),
  ('health',   'Health',   'ఆరోగ్యం',  '#15A34A', 2),
  ('business', 'Business', 'వ్యాపారం', '#4F46E5', 3),
  ('bakthi',   'Bhakthi',  'భక్తి',    '#EA580C', 4);

-- ============================================================
--  Auto-import the thumbnail from a YouTube video_id
--  (store only the id → derive the image URL on insert/update)
-- ============================================================
create or replace function set_youtube_thumbnail() returns trigger language plpgsql as $$
begin
  if new.source = 'youtube' and new.video_id is not null
     and (new.thumbnail_url is null or new.thumbnail_url = '') then
    new.thumbnail_url := 'https://img.youtube.com/vi/' || new.video_id || '/maxresdefault.jpg';
  end if;
  return new;
end $$;
create trigger trg_youtube_thumb
  before insert or update on articles
  for each row execute function set_youtube_thumbnail();

-- ============================================================
--  Seed: one community per category
-- ============================================================
insert into communities (slug, category_id, name, name_te, tagline, perks, members_count)
select v.slug, c.id, v.name, v.name_te, v.tagline, v.perks, v.members_count
from (values
  ('suman-news-room',      'news',     'Suman News Room',       'సుమన్ న్యూస్ రూమ్',     'Be first. Be informed. Be heard.',
     array['Breaking news alerts','Citizen journalism desk','Weekly debate nights','Newsroom press meets'], 58900),
  ('suman-health-tribe',   'health',   'Suman Health Tribe',    'సుమన్ హెల్త్ ట్రైబ్',   'Live healthier with doctors you actually trust.',
     array['Live doctor AMAs','Personalised diet plans','Sunday walkathons','Wellness goodie boxes'], 41200),
  ('suman-business-circle','business', 'Suman Business Circle',  'సుమన్ బిజినెస్ సర్కిల్', 'Founders, traders & money-minds of the Telugu states.',
     array['Weekly money webinars','City founder meetups','1:1 mentor matching','Member-only deals'], 24800),
  ('suman-bhakthi-sangham','bakthi',   'Suman Bhakthi Sangham', 'సుమన్ భక్తి సంఘం',      'Devotion, together.',
     array['Group temple yatras','Live-streamed poojas','Bhajan & kirtan nights','Prasadam gift drops'], 73500)
) as v(slug, cat_slug, name, name_te, tagline, perks, members_count)
join categories c on c.slug = v.cat_slug;

-- ============================================================
--  Seed: a few example reels (thumbnails auto-fill from video_id)
--  Replace video_id values with your real YouTube Short ids.
-- ============================================================
insert into articles (slug, category_id, title_en, title_te, source, source_url, video_id, channel, duration, views, keywords, is_featured, is_viral)
select v.slug, c.id, v.title_en, v.title_te, v.source::content_source, v.source_url, v.video_id, v.channel, v.duration, v.views, v.keywords, v.is_featured, v.is_viral
from (values
  ('hyderabad-metro-phase-2','news','Hyderabad Metro Phase 2: every new route revealed','హైదరాబాద్ మెట్రో ఫేజ్ 2: కొత్త మార్గాలు వెల్లడి','youtube','https://youtube.com/shorts/REPLACE1','REPLACE1','SumanTV News','0:48',3400000,array['Hyderabad','Metro','Infrastructure'],true,true),
  ('5pm-ragi-drink','health','The 5 PM ragi drink doctors quietly love','డాక్టర్లు మెచ్చే 5 గంటల రాగి జావ','youtube','https://youtube.com/shorts/REPLACE2','REPLACE2','SumanTV Health','0:52',2100000,array['Nutrition','Diabetes'],true,true),
  ('tiffin-cart-2cr','business','How a Hyderabad tiffin cart became a 2Cr brand','హైదరాబాద్ టిఫిన్ బండి కథ','youtube','https://youtube.com/shorts/REPLACE3','REPLACE3','SumanTV Business','0:58',1200000,array['Startup','Street Food'],true,true),
  ('tirumala-brahmotsavam','bakthi','Tirumala Brahmotsavam: live darshan timings','తిరుమల బ్రహ్మోత్సవం దర్శన సమయాలు','youtube','https://youtube.com/shorts/REPLACE4','REPLACE4','SumanTV Bhakthi','0:50',2700000,array['Tirumala','Festival'],true,true)
) as v(slug, cat_slug, title_en, title_te, source, source_url, video_id, channel, duration, views, keywords, is_featured, is_viral)
join categories c on c.slug = v.cat_slug;

-- ============================================================
--  Seed: a couple of events per community
-- ============================================================
insert into events (community_id, title, title_te, kind, starts_at, mode, host)
select cm.id, v.title, v.title_te, v.kind::event_kind, v.starts_at::timestamptz, v.mode, v.host
from (values
  ('suman-news-room',      'Citizen Journalism 101',          'సిటిజన్ జర్నలిజం 101',      'training',    '2026-06-21 19:00+05:30','Online',    'Newsroom Desk'),
  ('suman-news-room',      'Decoding the state budget',       'రాష్ట్ర బడ్జెట్ విశ్లేషణ',  'expert_talk', '2026-06-25 20:00+05:30','Online',    'Prof. Anil Kumar'),
  ('suman-health-tribe',   'Reverse pre-diabetes in 90 days', '90 రోజుల్లో ప్రీ-డయాబెటిస్','webinar',     '2026-06-20 18:00+05:30','Online',    'Dr. Latha Reddy'),
  ('suman-health-tribe',   'Sunday Wellness Walkathon',       'ఆదివారం వాకథాన్',           'meetup',      '2026-06-23 06:00+05:30','KBR Park',  'Health Tribe'),
  ('suman-business-circle','Hyderabad Founders Meetup',       'హైదరాబాద్ ఫౌండర్స్ మీటప్',  'meetup',      '2026-06-28 17:00+05:30','T-Hub',     'SumanTV Business'),
  ('suman-bhakthi-sangham','Live Satyanarayana Pooja',        'ప్రత్యక్ష సత్యనారాయణ పూజ',  'webinar',     '2026-06-24 07:00+05:30','Online',    'Sri Sharma Garu')
) as v(comm_slug, title, title_te, kind, starts_at, mode, host)
join communities cm on cm.slug = v.comm_slug;

-- ============================================================
--  Seed: ad slots (one per placement)
-- ============================================================
insert into ad_slots (placement, headline, sub, target_url) values
  ('leaderboard','Sponsored by Telugu Mart','Reach 4M+ daily viewers · 970×90 leaderboard','#'),
  ('infeed',     'Your ad could be here','In-feed native placement · category targeted','#'),
  ('sidebar',    'Premium 300×250','Sidebar display unit','#'),
  ('in_article', 'In-article advertisement','Native unit between paragraphs','#');
