const DEFAULT_TIMEOUT_MS = 30_000;

export class NotaeApiError extends Error {
  constructor(message, { status = null, details = null } = {}) {
    super(message);
    this.name = "NotaeApiError";
    this.status = status;
    this.details = details;
  }
}

export class NotaeApiClient {
  constructor({ baseUrl, token, fetchImpl = globalThis.fetch, timeoutMs = DEFAULT_TIMEOUT_MS }) {
    if (!baseUrl) throw new Error("NOTAE_BASE_URL is required");
    if (!token) throw new Error("NOTAE_API_TOKEN is required");
    if (typeof fetchImpl !== "function") throw new Error("A fetch implementation is required");

    this.baseUrl = baseUrl.replace(/\/+$/, "");
    this.token = token;
    this.fetchImpl = fetchImpl;
    this.timeoutMs = timeoutMs;
  }

  async listWorkspaces({ q, limit } = {}) {
    const payload = await this.request("/api/v1/workspaces", { query: compactQuery({ q, limit }) });
    return payload.data ?? [];
  }

  async listPages({ workspaceSlug, q, limit, pageKind } = {}) {
    const payload = await this.request(`/api/v1/workspaces/${encodeURIComponent(workspaceSlug)}/pages`, {
      query: compactQuery({ q, limit, page_kind: pageKind })
    });
    return payload.data ?? [];
  }

  async getPageMarkdown({ workspaceSlug, pageId }) {
    const payload = await this.request(`/api/v1/workspaces/${encodeURIComponent(workspaceSlug)}/pages/${encodeURIComponent(pageId)}/markdown`);
    return payload.data;
  }

  async createPageFromMarkdown({ workspaceSlug, title, markdown, parentPageId, permissionMode, filename }) {
    const payload = await this.request(`/api/v1/workspaces/${encodeURIComponent(workspaceSlug)}/pages/import_markdown`, {
      method: "POST",
      body: {
        page_document: compactObject({
          title,
          markdown,
          parent_page_id: parentPageId,
          permission_mode: permissionMode,
          filename
        })
      }
    });
    return payload.data;
  }

  async appendMarkdownToPage({ workspaceSlug, pageId, markdown, insertAfterBlockId, filename }) {
    const payload = await this.request(`/api/v1/workspaces/${encodeURIComponent(workspaceSlug)}/pages/${encodeURIComponent(pageId)}/append_markdown`, {
      method: "POST",
      body: {
        page_document: compactObject({
          markdown,
          insert_after_block_id: insertAfterBlockId,
          filename
        })
      }
    });
    return payload.data;
  }

  async listTaskLists({ workspaceSlug, q } = {}) {
    const payload = await this.request(`/api/v1/workspaces/${encodeURIComponent(workspaceSlug)}/databases`);
    const databases = payload.data ?? [];

    if (!q) return databases;

    const pattern = q.toLowerCase();
    return databases.filter((database) => database.name?.toLowerCase().includes(pattern));
  }

  async listCalendars({ workspaceSlug, writable = true } = {}) {
    const payload = await this.request(`/api/v1/workspaces/${encodeURIComponent(workspaceSlug)}/kalendarium/calendars`, {
      query: compactQuery({ writable: writable ? "1" : undefined })
    });
    return payload.data ?? [];
  }

  async createCalendarEvent({
    workspaceSlug,
    calendarId,
    title,
    startsAt,
    endsAt,
    timeZone,
    allDay,
    description,
    location,
    meetingJoinUrl,
    reminderOffsetsMinutes
  }) {
    const payload = await this.request(`/api/v1/workspaces/${encodeURIComponent(workspaceSlug)}/kalendarium/events`, {
      method: "POST",
      body: {
        kalendarium_event: compactObject({
          kalendarium_calendar_id: calendarId,
          title,
          starts_at: startsAt,
          ends_at: endsAt,
          time_zone: timeZone,
          all_day: allDay,
          description,
          location,
          meeting_join_url: meetingJoinUrl,
          reminder_offsets_minutes: reminderOffsetsMinutes
        })
      }
    });
    return payload.data;
  }

  async sendCodexCompletionPush({ workspaceSlug, title, body, path } = {}) {
    const payload = await this.request(`/api/v1/workspaces/${encodeURIComponent(workspaceSlug)}/notifications/codex_completion`, {
      method: "POST",
      body: {
        notification: compactObject({
          title,
          body,
          path
        })
      }
    });
    return payload.data;
  }

  async listAgentActions({ workspaceSlug, status, limit } = {}) {
    const payload = await this.request(`/api/v1/workspaces/${encodeURIComponent(workspaceSlug)}/agent_actions`, {
      query: compactQuery({ status, limit })
    });
    return payload.data ?? [];
  }

  async getAgentAction({ workspaceSlug, agentActionId }) {
    const payload = await this.request(`/api/v1/workspaces/${encodeURIComponent(workspaceSlug)}/agent_actions/${encodeURIComponent(agentActionId)}`);
    return payload.data;
  }

  async createAgentAction({ workspaceSlug, title, targetSystem, draftType, payloadJson, metadataJson, proposedBy = "api" }) {
    const payload = await this.request(`/api/v1/workspaces/${encodeURIComponent(workspaceSlug)}/agent_actions`, {
      method: "POST",
      body: {
        agent_action: compactObject({
          title,
          proposed_by: proposedBy,
          target_system: targetSystem,
          draft_type: draftType,
          payload_json: payloadJson,
          metadata_json: metadataJson
        })
      }
    });
    return payload.data;
  }

  async approveAgentAction({ workspaceSlug, agentActionId, decisionComment, destinationDatabaseId, destinationCalendarId }) {
    const payload = await this.request(`/api/v1/workspaces/${encodeURIComponent(workspaceSlug)}/agent_actions/${encodeURIComponent(agentActionId)}/approve`, {
      method: "POST",
      body: compactObject({
        decision_comment: decisionComment,
        destination_database_id: destinationDatabaseId,
        destination_calendar_id: destinationCalendarId
      })
    });
    return payload.data;
  }

  async request(path, { method = "GET", query, body } = {}) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      const response = await this.fetchImpl(buildUrl(this.baseUrl, path, query), {
        method,
        headers: {
          Accept: "application/json",
          Authorization: `Bearer ${this.token}`,
          ...(body ? { "Content-Type": "application/json" } : {})
        },
        body: body ? JSON.stringify(body) : undefined,
        signal: controller.signal
      });

      const payload = await parseResponse(response);
      if (!response.ok) {
        const message = payload?.error?.message || payload?.message || `Notae API request failed with status ${response.status}`;
        throw new NotaeApiError(message, { status: response.status, details: payload?.error?.details ?? null });
      }

      return payload;
    } catch (error) {
      if (error?.name === "AbortError") {
        throw new NotaeApiError("Notae API request timed out");
      }

      if (error instanceof NotaeApiError) throw error;
      throw new NotaeApiError(error?.message || "Notae API request failed");
    } finally {
      clearTimeout(timeout);
    }
  }
}

export function buildUrl(baseUrl, path, query) {
  const url = new URL(path, `${baseUrl}/`);
  for (const [ key, value ] of Object.entries(query ?? {})) {
    if (value === undefined || value === null || value === "") continue;
    url.searchParams.set(key, String(value));
  }
  return url;
}

export function compactObject(value) {
  return Object.fromEntries(
    Object.entries(value ?? {}).filter(([, entry ]) => entry !== undefined && entry !== null && entry !== "")
  );
}

export function compactQuery(value) {
  return compactObject(value);
}

async function parseResponse(response) {
  const contentType = response.headers.get("content-type") || "";
  if (contentType.includes("application/json")) {
    return response.json();
  }

  const text = await response.text();
  return text ? { message: text } : {};
}
