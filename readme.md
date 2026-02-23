# Notae

Block-based collaborative workspace built with Rails 8.1 + Ruby 4 + Postgres.

---

## Overview

Notae is a structured, permission-aware knowledge system designed for teams. It supports:

- Multi-workspace tenancy (single Postgres DB)
- Nested pages and block-based editing (TipTap)
- Structured databases (table view v1)
- Search and backlinks
- Comments and mentions
- Attachments
- Version history
- Audit logging

Public sharing, real-time collaboration, and encryption are planned for later phases.

---

## Stack

- Ruby 4.x
- Rails 8.1.x
- Postgres 15+
- Devise
- Pundit
- TipTap (ProseMirror JSON storage)
- PgSearch
- PaperTrail
- Sidekiq + Redis
- ActiveStorage
- RSpec

---

## Tenancy Model

Single Postgres database.
Every domain entity contains `workspace_id`.
All queries must be scoped to workspace and filtered via Pundit policy scopes.

No cross-workspace queries are allowed.

---

## Editor Architecture

TipTap is used from day one.

- Blocks store ProseMirror JSON in `content_json`
- Slash commands supported
- Nested block hierarchy
- JSON schema must remain stable for mobile ports later

No ActionText is used.

---

## Core Models

User  
Workspace  
Membership  
Invitation  

Page  
Block  

Database  
DbProperty  
DbRow  
DbCell  

Comment  
Notification  
PageLink  
AuditEvent  

---

## Development Setup

### Install
bundle install  
bin/rails db:prepare  

### Run
bin/dev  

### Test
bundle exec rspec  

### Lint
bundle exec rubocop  
bundle exec brakeman  

---

## Development Rules

- UUID primary keys for user-facing entities
- Use DB constraints + indexes
- No N+1 queries in main views
- All controllers must enforce Pundit authorization
- Search must use policy scope filtering
- All destructive actions must create AuditEvent

---

## MVP Definition of Done

- Multi-workspace support working
- Block editor fully functional
- Database table view usable
- Search works across workspace
- Backlinks visible
- Comments + notifications working
- File uploads working
- Version restore working
- Trash/restore working
- Permission tests passing