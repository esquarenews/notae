const AUTO_PUSH_TOOL_MESSAGES = {
  create_page_from_markdown: {
    title: "Notae page created",
    path: ({ workspaceSlug, result }) => `/w/${workspaceSlug}/pages/${result?.page?.id || ""}`,
    body: ({ result }) => result?.page?.title ? `Created page: ${result.page.title}` : "Created a page from Markdown."
  },
  append_markdown_to_page: {
    title: "Notae page updated",
    path: ({ workspaceSlug, result }) => `/w/${workspaceSlug}/pages/${result?.page?.id || ""}`,
    body: ({ result }) => result?.page?.title ? `Updated page: ${result.page.title}` : "Appended Markdown to a page."
  },
  delete_grid_row: {
    title: "Grid row archived",
    path: ({ workspaceSlug, result }) => `/w/${workspaceSlug}/databases/${result?.row?.database_id || ""}`,
    body: ({ result }) => result?.row?.title ? `Archived row: ${result.row.title}` : "Archived a grid row."
  },
  set_grid_row_nota_link: {
    title: "Grid row Nota link updated",
    path: ({ workspaceSlug, result }) => (
      result?.row?.linked_page_id
        ? `/w/${workspaceSlug}/pages/${result.row.linked_page_id}`
        : `/w/${workspaceSlug}/databases/${result?.row?.database_id || ""}`
    ),
    body: ({ result }) => {
      if (!result?.row) return "Updated a grid row Nota link.";
      if (!result.row.linked_page_id) return `Cleared linked Nota for row: ${result.row.title}`;
      return `Linked row "${result.row.title}" to ${result.row.linked_page?.title || "a Nota"}.`;
    }
  },
  create_calendar_event: {
    title: "Calendar event created",
    path: ({ result }) => result?.url || undefined,
    body: ({ result }) => result?.event?.title ? `Created event: ${result.event.title}` : "Created a calendar event."
  },
  create_agent_action: {
    title: "Agent action created",
    path: ({ workspaceSlug }) => `/w/${workspaceSlug}/agent_actions`,
    body: ({ result }) => result?.title ? `Created draft: ${result.title}` : "Created an agent action."
  },
  approve_agent_action: {
    title: "Agent action completed",
    path: ({ workspaceSlug, result }) => result?.result_json?.url || `/w/${workspaceSlug}/agent_actions/${result?.id || ""}`,
    body: ({ result }) => result?.title ? `Completed action: ${result.title}` : "Approved an agent action."
  }
};

export function autoPushConfigFor(toolName) {
  return AUTO_PUSH_TOOL_MESSAGES[toolName] || null;
}

export function buildAutoPushPayload(toolName, { workspaceSlug, result }) {
  const config = autoPushConfigFor(toolName);
  if (!config || !workspaceSlug) return null;

  const path = normalizeInternalPath(config.path?.({ workspaceSlug, result }));
  const body = normalizeText(config.body?.({ workspaceSlug, result }));

  return {
    workspaceSlug,
    title: config.title,
    body,
    path
  };
}

function normalizeInternalPath(value) {
  const path = normalizeText(value);
  if (!path || !path.startsWith("/")) return undefined;
  return path;
}

function normalizeText(value) {
  const text = value?.toString().trim();
  return text ? text : undefined;
}
