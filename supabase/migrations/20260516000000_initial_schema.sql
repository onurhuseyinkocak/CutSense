-- CutSense Initial Schema
-- All tables have RLS enabled with user-only access policies

-- profiles
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  avatar_url text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  last_login_at timestamptz
);

alter table public.profiles enable row level security;

create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);
create policy "profiles_insert_own" on public.profiles
  for insert with check (auth.uid() = id);
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id);

-- projects
create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  original_duration double precision,
  final_duration double precision,
  status text not null default 'draft',
  selected_template text,
  source_local_identifier text,
  source_file_name text,
  local_project_path text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.projects enable row level security;

create policy "projects_select_own" on public.projects
  for select using (auth.uid() = user_id);
create policy "projects_insert_own" on public.projects
  for insert with check (auth.uid() = user_id);
create policy "projects_update_own" on public.projects
  for update using (auth.uid() = user_id);
create policy "projects_delete_own" on public.projects
  for delete using (auth.uid() = user_id);

-- transcripts
create table if not exists public.transcripts (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  full_text text,
  language text,
  confidence double precision,
  created_at timestamptz default now()
);

alter table public.transcripts enable row level security;

create policy "transcripts_select_own" on public.transcripts
  for select using (auth.uid() = user_id);
create policy "transcripts_insert_own" on public.transcripts
  for insert with check (auth.uid() = user_id);
create policy "transcripts_update_own" on public.transcripts
  for update using (auth.uid() = user_id);
create policy "transcripts_delete_own" on public.transcripts
  for delete using (auth.uid() = user_id);

-- transcript_segments
create table if not exists public.transcript_segments (
  id uuid primary key default gen_random_uuid(),
  transcript_id uuid not null references public.transcripts(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  start_time double precision not null,
  end_time double precision not null,
  text text not null,
  confidence double precision,
  segment_type text,
  created_at timestamptz default now()
);

alter table public.transcript_segments enable row level security;

create policy "transcript_segments_select_own" on public.transcript_segments
  for select using (auth.uid() = user_id);
create policy "transcript_segments_insert_own" on public.transcript_segments
  for insert with check (auth.uid() = user_id);
create policy "transcript_segments_update_own" on public.transcript_segments
  for update using (auth.uid() = user_id);
create policy "transcript_segments_delete_own" on public.transcript_segments
  for delete using (auth.uid() = user_id);

-- rough_cut_decisions
create table if not exists public.rough_cut_decisions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  start_time double precision not null,
  end_time double precision not null,
  action text not null,
  reason text not null,
  confidence double precision not null,
  linked_transcript_text text,
  requires_review boolean default false,
  created_at timestamptz default now()
);

alter table public.rough_cut_decisions enable row level security;

create policy "rough_cut_decisions_select_own" on public.rough_cut_decisions
  for select using (auth.uid() = user_id);
create policy "rough_cut_decisions_insert_own" on public.rough_cut_decisions
  for insert with check (auth.uid() = user_id);
create policy "rough_cut_decisions_update_own" on public.rough_cut_decisions
  for update using (auth.uid() = user_id);
create policy "rough_cut_decisions_delete_own" on public.rough_cut_decisions
  for delete using (auth.uid() = user_id);

-- take_groups
create table if not exists public.take_groups (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  group_label text,
  semantic_summary text,
  selected_take_id uuid,
  confidence double precision,
  created_at timestamptz default now()
);

alter table public.take_groups enable row level security;

create policy "take_groups_select_own" on public.take_groups
  for select using (auth.uid() = user_id);
create policy "take_groups_insert_own" on public.take_groups
  for insert with check (auth.uid() = user_id);
create policy "take_groups_update_own" on public.take_groups
  for update using (auth.uid() = user_id);
create policy "take_groups_delete_own" on public.take_groups
  for delete using (auth.uid() = user_id);

-- takes
create table if not exists public.takes (
  id uuid primary key default gen_random_uuid(),
  take_group_id uuid not null references public.take_groups(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  start_time double precision not null,
  end_time double precision not null,
  text text not null,
  score double precision not null,
  score_reason text,
  is_selected boolean default false,
  created_at timestamptz default now()
);

alter table public.takes enable row level security;

create policy "takes_select_own" on public.takes
  for select using (auth.uid() = user_id);
create policy "takes_insert_own" on public.takes
  for insert with check (auth.uid() = user_id);
create policy "takes_update_own" on public.takes
  for update using (auth.uid() = user_id);
create policy "takes_delete_own" on public.takes
  for delete using (auth.uid() = user_id);

-- caption_segments
create table if not exists public.caption_segments (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  start_time double precision not null,
  end_time double precision not null,
  text text not null,
  role text not null,
  style text not null,
  scene_behavior text,
  created_at timestamptz default now()
);

alter table public.caption_segments enable row level security;

create policy "caption_segments_select_own" on public.caption_segments
  for select using (auth.uid() = user_id);
create policy "caption_segments_insert_own" on public.caption_segments
  for insert with check (auth.uid() = user_id);
create policy "caption_segments_update_own" on public.caption_segments
  for update using (auth.uid() = user_id);
create policy "caption_segments_delete_own" on public.caption_segments
  for delete using (auth.uid() = user_id);

-- edit_decisions
create table if not exists public.edit_decisions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  start_time double precision not null,
  end_time double precision,
  type text not null,
  reason text not null,
  intensity double precision not null,
  linked_caption_id uuid references public.caption_segments(id) on delete set null,
  created_at timestamptz default now()
);

alter table public.edit_decisions enable row level security;

create policy "edit_decisions_select_own" on public.edit_decisions
  for select using (auth.uid() = user_id);
create policy "edit_decisions_insert_own" on public.edit_decisions
  for insert with check (auth.uid() = user_id);
create policy "edit_decisions_update_own" on public.edit_decisions
  for update using (auth.uid() = user_id);
create policy "edit_decisions_delete_own" on public.edit_decisions
  for delete using (auth.uid() = user_id);

-- exports
create table if not exists public.exports (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  local_file_name text,
  local_identifier text,
  duration double precision,
  resolution text,
  template_name text,
  file_size_bytes bigint,
  created_at timestamptz default now()
);

alter table public.exports enable row level security;

create policy "exports_select_own" on public.exports
  for select using (auth.uid() = user_id);
create policy "exports_insert_own" on public.exports
  for insert with check (auth.uid() = user_id);
create policy "exports_update_own" on public.exports
  for update using (auth.uid() = user_id);
create policy "exports_delete_own" on public.exports
  for delete using (auth.uid() = user_id);

-- Handle new user profile creation
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, display_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)));
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
