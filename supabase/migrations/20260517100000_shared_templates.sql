-- Shared templates for community template hub
create table if not exists public.shared_templates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  author_name text not null default 'Anonymous',
  template_data jsonb not null,
  name text not null,
  description text not null default '',
  downloads integer not null default 0,
  rating_sum integer not null default 0,
  rating_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.shared_templates enable row level security;

-- Anyone authenticated can browse
create policy "shared_templates_select_all" on public.shared_templates
  for select using (auth.role() = 'authenticated');

-- Only owner can insert/update/delete their own
create policy "shared_templates_insert_own" on public.shared_templates
  for insert with check (auth.uid() = user_id);

create policy "shared_templates_update_own" on public.shared_templates
  for update using (auth.uid() = user_id);

create policy "shared_templates_delete_own" on public.shared_templates
  for delete using (auth.uid() = user_id);

-- Ratings table (one per user per template)
create table if not exists public.template_ratings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  template_id uuid not null references public.shared_templates(id) on delete cascade,
  rating integer not null check (rating >= 1 and rating <= 5),
  created_at timestamptz not null default now(),
  unique(user_id, template_id)
);

alter table public.template_ratings enable row level security;

create policy "template_ratings_select_all" on public.template_ratings
  for select using (auth.role() = 'authenticated');

create policy "template_ratings_insert_own" on public.template_ratings
  for insert with check (auth.uid() = user_id);

create policy "template_ratings_update_own" on public.template_ratings
  for update using (auth.uid() = user_id);

create policy "template_ratings_delete_own" on public.template_ratings
  for delete using (auth.uid() = user_id);

-- Index for browsing sorted by popularity
create index idx_shared_templates_downloads on public.shared_templates(downloads desc);
create index idx_shared_templates_rating on public.shared_templates(rating_count desc);
create index idx_shared_templates_created on public.shared_templates(created_at desc);
