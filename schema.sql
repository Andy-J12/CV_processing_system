create table candidates (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text,
  phone text,
  years_experience numeric,
  skills text[] default '{}',
  education jsonb default '[]',
  experience jsonb default '[]',
  classification text check (classification in ('junior', 'semi-senior', 'senior')),
  classification_reason text,
  cv_file_url text,
  source_email_id text unique,
  status text default 'pending' check (status in ('pending', 'notified', 'reviewed')),
  created_at timestamptz default now()
);

create index idx_candidates_skills on candidates using gin (skills);
create index idx_candidates_source_email on candidates (source_email_id);
