-- Backend pipeline: jobs + edit_manifests (EditManifest = single source of truth).
-- Workers (service role) bypass RLS; clients read only their own.

create table if not exists public.jobs (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references public.projects(id) on delete set null,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'queued',
  progress int not null default 0,
  error text,
  raw_r2_key text,
  final_r2_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.jobs enable row level security;

create policy "jobs_select_own" on public.jobs for select using (auth.uid() = user_id);
create policy "jobs_insert_own" on public.jobs for insert with check (auth.uid() = user_id);
create policy "jobs_update_own" on public.jobs for update using (auth.uid() = user_id);
create policy "jobs_delete_own" on public.jobs for delete using (auth.uid() = user_id);

create index if not exists jobs_user_idx on public.jobs (user_id, created_at desc);

create table if not exists public.edit_manifests (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  version int not null default 1,
  manifest jsonb not null,
  created_at timestamptz not null default now()
);

alter table public.edit_manifests enable row level security;

-- Read only manifests for jobs you own. Writes are service-role only (worker).
create policy "manifests_select_own" on public.edit_manifests for select using (
  exists (select 1 from public.jobs j where j.id = edit_manifests.job_id and j.user_id = auth.uid())
);

create index if not exists manifests_job_idx on public.edit_manifests (job_id, created_at desc);
