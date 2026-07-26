# CV Processing Automation with n8n + AI

An end-to-end automation pipeline that receives CVs by email, extracts and classifies candidate data using LLMs, and stores structured results in a database — with automatic recruiter notifications.

Built with **n8n**, **Gmail API**, **Dropbox API**, **DeepSeek** (LLM), and **Supabase (PostgreSQL)**.

## What it does

1. Detects incoming emails tagged as job applications (via a Gmail label + filter)
2. Handles multiple PDF attachments per email independently
3. Validates each attachment is actually a PDF
4. Backs up the original file to Dropbox
5. Uses an LLM to determine whether the document is genuinely a CV, and if so, extracts structured data (name, contact info, skills, education, work experience, calculated years of experience)
6. Checks for duplicates against existing records before processing further
7. Uses a second LLM call to classify the candidate (junior / semi-senior / senior) with a reasoning explanation
8. Persists the candidate record in a PostgreSQL database (via Supabase)
9. Sends an automatic email notification summarizing the new candidate

## Architecture

```
Gmail Trigger → Get Message → Split Attachments → Normalize Binary
      ↓
Validate PDF ──┬─→ Backup to Dropbox
               └─→ AI Extraction (LLM) → Parse JSON
      ↓
Merge (candidate data + file info)
      ↓
Loop Over Items (one candidate at a time)
      ↓
Duplicate Check (Supabase) ──true──→ AI Classification (LLM) → Insert Row → Send Notification ──┐
      │false                                                                                       │
      └──────────────────────────────────────────────────────────────────────────────────────────→ back to Loop
```

The workflow processes one candidate at a time through a loop, which keeps the duplicate-check and classification logic simple and avoids data cross-contamination between parallel items — a real issue encountered and solved during development (see Lessons Learned).

## Tech stack

| Component | Tool |
|---|---|
| Orchestration | n8n (self-hosted via Docker) |
| Tunneling | ngrok |
| Email trigger & notifications | Gmail API (OAuth2) |
| File storage | Dropbox API |
| AI extraction & classification | DeepSeek API (`deepseek-chat`) — originally built with Gemini, migrated for cost/rate-limit reasons |
| Database | Supabase (PostgreSQL) |

## Database schema

```sql
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
```

`source_email_id` is unique and used as the deduplication key, so the same email thread is never processed twice.

## Repository structure

```
CV_processing_system/
├── README.md
├── schema.sql                      Database schema (run once in Supabase's SQL Editor)
├── .env.example                    Credential placeholders — never commit the real .env
├── .gitignore
├── CV processing system.json       n8n workflow export (import this into n8n)
└── Test/                           Screenshots proving the pipeline works end-to-end
    ├── docker_container.PNG        n8n running in Docker
    ├── ngrok_service.PNG           ngrok tunnel active (needed for OAuth redirect URLs)
    ├── supabase_table.PNG          Candidates table in Supabase after processing
    ├── email_1.PNG / email_2.PNG   Test application emails sent to trigger the workflow
    └── test_1.PNG / test_2.PNG / Final_test.PNG   Resulting classification notifications
```

## Setup

### Prerequisites
- Docker
- n8n running locally (or via Docker)
- ngrok (or another tunneling solution, for OAuth redirect URLs)
- A Google Cloud project with Gmail API enabled
- A Dropbox app with API access
- A Supabase project
- A DeepSeek API key

### Steps

1. Clone this repo and copy `.env.example` to `.env`, filling in your own credentials
2. Run the SQL in `schema.sql` inside your Supabase project's SQL Editor
3. Start n8n (Docker) and import `CV processing system.json`
4. Expose n8n with ngrok so Google/Dropbox can reach the OAuth redirect URL
5. In Gmail, create a label (e.g. `CVs-recibidos`) and a filter that auto-applies it to incoming applications (e.g. subject contains "CV" or "postulación" AND has an attachment)
6. Configure credentials inside n8n for: Gmail (OAuth2), Dropbox (OAuth2), Supabase (API key), DeepSeek (API key)
7. Activate the workflow

## Testing

See the `Test/` folder for visual proof the pipeline works: emails sent with test CVs (`email_1.PNG`, `email_2.PNG`), the resulting AI-generated classification notifications (`test_1.PNG`, `test_2.PNG`, `Final_test.PNG`), the populated Supabase table (`supabase_table.PNG`), and the running infrastructure (`docker_container.PNG`, `ngrok_service.PNG`).

The pipeline was tested with:
- Single emails with one CV attachment
- A single email with multiple mixed attachments (some CVs, some unrelated documents) — verifying the LLM correctly discards non-CV files
- Multiple emails sent in quick succession — verifying the Loop Over Items pattern correctly processes each candidate sequentially without data cross-contamination
- Duplicate submissions — verifying `source_email_id` prevents double-processing

## Lessons learned / notable challenges

- **Multiple attachments per email**: a single email can contain several PDFs, not all of which are CVs. Solved by splitting binary attachments into individual items and letting the LLM itself judge whether each document is a genuine CV, rather than relying on filename heuristics.
- **Item context loss across nodes**: n8n nodes that query external data (e.g. Supabase "Get Many") can break the automatic item-pairing n8n uses for cross-node references. Solved using an explicit Merge node (combine by position) instead of relying on ambiguous `$('NodeName').item` expressions.
- **Batch vs. per-item execution**: several bugs traced back to Code nodes running in "Run Once for All Items" mode when "Run Once for Each Item" was required — a subtle but important n8n setting.
- **Provider migration mid-project**: started with Gemini, hit persistent free-tier rate limits, migrated the AI extraction and classification steps to DeepSeek without changing the rest of the pipeline — demonstrating the pipeline's LLM-provider independence.

## Disclaimer

Test CVs used during development belong to real people who provided them for testing purposes. Do not use this repository's test data for any purpose other than understanding the workflow.
