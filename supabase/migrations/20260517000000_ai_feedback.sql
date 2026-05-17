-- AI Feedback: stores user overrides of AI classification decisions
-- Used to improve on-device LLM prompts with few-shot examples

create table if not exists public.ai_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  segment_text text not null,
  ai_classification text not null,
  ai_confidence double precision,
  ai_reason text,
  user_action text not null,
  language text,
  created_at timestamptz default now()
);

alter table public.ai_feedback enable row level security;

create policy "ai_feedback_select_own" on public.ai_feedback
  for select using (auth.uid() = user_id);
create policy "ai_feedback_insert_own" on public.ai_feedback
  for insert with check (auth.uid() = user_id);
create policy "ai_feedback_delete_own" on public.ai_feedback
  for delete using (auth.uid() = user_id);

-- Index for fetching recent feedback per user
create index idx_ai_feedback_user_recent on public.ai_feedback (user_id, created_at desc);
