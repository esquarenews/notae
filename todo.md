# Notae — Future Phases

---

## Phase 2

- Public share links (token-based, revocable)
- Real-time presence via ActionCable
- Live block updates
- Board view for databases
- Calendar view for databases
- Export to Markdown
- Keyboard shortcut expansion
- Performance optimizations
- API versioning for mobile

---

## Phase 3

### End-to-End Encryption (E2EE)

Design goals:
- Client-side encryption of block content
- Encrypted JSON payload stored server-side
- Key management per workspace
- Invite flow includes secure key exchange
- Server never sees decrypted content
- Backups support encrypted data

Implications:
- Search must move client-side or use encrypted index strategy
- Mentions may require metadata split from encrypted body
- Attachment encryption required
- Conflict resolution complexity increases

---

## Phase 4

- Native mobile apps (iOS + Android)
- Offline sync model
- Operational Transform / CRDT for real-time editing
- Granular analytics
- Workspace templates marketplace