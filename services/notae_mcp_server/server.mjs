import { McpServer, ResourceTemplate } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

import { NotaeApiClient, NotaeApiError } from "./client.mjs";

const server = new McpServer({
  name: "notae",
  version: "0.1.0"
});

const client = new NotaeApiClient({
  baseUrl: process.env.NOTAE_BASE_URL,
  token: process.env.NOTAE_API_TOKEN
});

const pageResourceTemplate = new ResourceTemplate("notae://workspace/{workspaceSlug}/pages/{pageId}.md", { list: undefined });

server.registerResource(
  "notae-page-markdown",
  pageResourceTemplate,
  {
    title: "Notae Page Markdown",
    description: "Read a Notae page as Markdown by workspace slug and page id.",
    mimeType: "text/markdown"
  },
  async (_uri, { workspaceSlug, pageId }) => {
    const pageDocument = await client.getPageMarkdown({ workspaceSlug, pageId });
    return {
      contents: [
        {
          uri: `notae://workspace/${workspaceSlug}/pages/${pageId}.md`,
          mimeType: "text/markdown",
          text: pageDocument.markdown
        }
      ]
    };
  }
);

server.registerTool(
  "list_workspaces",
  {
    title: "List Notae Workspaces",
    description: "List Notae workspaces accessible to the configured API token.",
    inputSchema: {
      q: z.string().optional(),
      limit: z.number().int().min(1).max(100).optional()
    },
    outputSchema: {
      workspaces: z.array(z.object({
        id: z.string(),
        name: z.string(),
        slug: z.string(),
        role: z.string().nullable().optional()
      }))
    }
  },
  async ({ q, limit }) => runTool(async () => {
    const workspaces = await client.listWorkspaces({ q, limit });
    return successResult({
      text: renderWorkspaces(workspaces),
      data: { workspaces }
    });
  })
);

server.registerTool(
  "search_pages",
  {
    title: "Search Notae Pages",
    description: "Search pages in a workspace by title. Use page_kind='nota' to narrow to regular notas.",
    inputSchema: {
      workspace_slug: z.string(),
      q: z.string().optional(),
      limit: z.number().int().min(1).max(100).optional(),
      page_kind: z.enum([ "nota", "meeting_note" ]).optional()
    },
    outputSchema: {
      pages: z.array(z.object({
        id: z.string(),
        title: z.string(),
        permission_mode: z.string(),
        updated_at: z.string().nullable().optional()
      }))
    }
  },
  async ({ workspace_slug: workspaceSlug, q, limit, page_kind: pageKind }) => runTool(async () => {
    const pages = await client.listPages({ workspaceSlug, q, limit, pageKind });
    return successResult({
      text: renderPages(pages),
      data: { pages }
    });
  })
);

server.registerTool(
  "read_page_markdown",
  {
    title: "Read Notae Page Markdown",
    description: "Export a Notae page as Markdown.",
    inputSchema: {
      workspace_slug: z.string(),
      page_id: z.string()
    },
    outputSchema: {
      page: z.object({
        id: z.string(),
        title: z.string()
      }),
      markdown: z.string(),
      attachments: z.array(z.object({
        filename: z.string(),
        relative_path: z.string()
      }))
    }
  },
  async ({ workspace_slug: workspaceSlug, page_id: pageId }) => runTool(async () => {
    const pageDocument = await client.getPageMarkdown({ workspaceSlug, pageId });
    return successResult({
      text: pageDocument.markdown,
      data: pageDocument
    });
  })
);

server.registerTool(
  "create_page_from_markdown",
  {
    title: "Create Notae Page From Markdown",
    description: "Create a new Notae page and import Markdown content into it.",
    inputSchema: {
      workspace_slug: z.string(),
      title: z.string(),
      markdown: z.string(),
      parent_page_id: z.string().optional(),
      permission_mode: z.enum([ "shared_to_workspace", "private_page", "specific_users" ]).optional(),
      filename: z.string().optional()
    },
    outputSchema: {
      page: z.object({
        id: z.string(),
        title: z.string()
      }),
      imported_blocks: z.array(z.object({
        id: z.string(),
        block_type: z.string()
      })),
      skipped_documents: z.array(z.string())
    }
  },
  async ({ workspace_slug: workspaceSlug, title, markdown, parent_page_id: parentPageId, permission_mode: permissionMode, filename }) => runTool(async () => {
    const result = await client.createPageFromMarkdown({ workspaceSlug, title, markdown, parentPageId, permissionMode, filename });
    return successResult({
      text: `Created page "${result.page.title}" (${result.page.id}) with ${result.imported_blocks.length} imported block(s).`,
      data: result
    });
  })
);

server.registerTool(
  "append_markdown_to_page",
  {
    title: "Append Markdown To Notae Page",
    description: "Append Markdown content to an existing Notae page. Optionally insert after a specific block id.",
    inputSchema: {
      workspace_slug: z.string(),
      page_id: z.string(),
      markdown: z.string(),
      insert_after_block_id: z.string().optional(),
      filename: z.string().optional()
    },
    outputSchema: {
      page: z.object({
        id: z.string(),
        title: z.string()
      }),
      imported_blocks: z.array(z.object({
        id: z.string(),
        block_type: z.string()
      })),
      skipped_documents: z.array(z.string())
    }
  },
  async ({ workspace_slug: workspaceSlug, page_id: pageId, markdown, insert_after_block_id: insertAfterBlockId, filename }) => runTool(async () => {
    const result = await client.appendMarkdownToPage({ workspaceSlug, pageId, markdown, insertAfterBlockId, filename });
    return successResult({
      text: `Appended ${result.imported_blocks.length} block(s) to page ${result.page.title}.`,
      data: result
    });
  })
);

server.registerTool(
  "list_task_lists",
  {
    title: "List Notae Task Lists",
    description: "List Notae databases/task lists in a workspace. Use this before approving task drafts.",
    inputSchema: {
      workspace_slug: z.string(),
      q: z.string().optional()
    },
    outputSchema: {
      task_lists: z.array(z.object({
        id: z.string(),
        name: z.string(),
        row_count: z.number().optional()
      }))
    }
  },
  async ({ workspace_slug: workspaceSlug, q }) => runTool(async () => {
    const taskLists = await client.listTaskLists({ workspaceSlug, q });
    return successResult({
      text: renderTaskLists(taskLists),
      data: { task_lists: taskLists }
    });
  })
);

server.registerTool(
  "list_calendars",
  {
    title: "List Notae Calendars",
    description: "List writable Notae calendars in a workspace. Use this before approving calendar drafts or creating events.",
    inputSchema: {
      workspace_slug: z.string()
    },
    outputSchema: {
      calendars: z.array(z.object({
        id: z.string(),
        name: z.string(),
        read_only: z.boolean().optional(),
        writable: z.boolean().optional()
      }))
    }
  },
  async ({ workspace_slug: workspaceSlug }) => runTool(async () => {
    const calendars = await client.listCalendars({ workspaceSlug });
    return successResult({
      text: renderCalendars(calendars),
      data: { calendars }
    });
  })
);

server.registerTool(
  "create_calendar_event",
  {
    title: "Create Notae Calendar Event",
    description: "Create a Notae calendar event directly on a writable calendar in a workspace.",
    inputSchema: {
      workspace_slug: z.string(),
      calendar_id: z.string(),
      title: z.string(),
      starts_at: z.string(),
      ends_at: z.string(),
      time_zone: z.string().optional(),
      all_day: z.boolean().optional(),
      description: z.string().optional(),
      location: z.string().optional(),
      meeting_join_url: z.string().optional(),
      reminder_offsets_minutes: z.array(z.number().int().min(0)).optional()
    },
    outputSchema: {
      event: z.object({
        id: z.string(),
        calendar_id: z.string(),
        title: z.string(),
        starts_at_utc: z.string().nullable().optional(),
        ends_at_utc: z.string().nullable().optional(),
        all_day: z.boolean(),
        status: z.string(),
        visibility: z.string()
      }),
      url: z.string().optional(),
      warning: z.string().optional()
    }
  },
  async ({ workspace_slug: workspaceSlug, calendar_id: calendarId, title, starts_at: startsAt, ends_at: endsAt, time_zone: timeZone, all_day: allDay, description, location, meeting_join_url: meetingJoinUrl, reminder_offsets_minutes: reminderOffsetsMinutes }) => runTool(async () => {
    const result = await client.createCalendarEvent({
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
    });
    return successResult({
      text: renderCreatedCalendarEvent(result),
      data: result
    });
  })
);

server.registerTool(
  "list_agent_actions",
  {
    title: "List Notae Agent Actions",
    description: "List agent-action drafts and outcomes in a workspace.",
    inputSchema: {
      workspace_slug: z.string(),
      status: z.enum([ "pending", "changes_requested", "approved", "rejected", "failed" ]).optional(),
      limit: z.number().int().min(1).max(100).optional()
    },
    outputSchema: {
      agent_actions: z.array(z.object({
        id: z.string(),
        title: z.string(),
        draft_type: z.string(),
        target_system: z.string(),
        status: z.string()
      }))
    }
  },
  async ({ workspace_slug: workspaceSlug, status, limit }) => runTool(async () => {
    const agentActions = await client.listAgentActions({ workspaceSlug, status, limit });
    return successResult({
      text: renderAgentActions(agentActions),
      data: { agent_actions: agentActions }
    });
  })
);

server.registerTool(
  "create_agent_action",
  {
    title: "Create Notae Agent Action",
    description: "Create a pending Notae agent-action draft. Use payload_json {title, body} for nota_draft; {project, title, body, assignee?, due_at?} for task_ticket; {title, starts_at, ends_at, body?, attendees?} for calendar_hold.",
    inputSchema: {
      workspace_slug: z.string(),
      title: z.string(),
      target_system: z.enum([ "gmail", "email", "github", "slack", "calendar", "crm", "notae" ]),
      draft_type: z.enum([ "email_draft", "github_comment_draft", "task_ticket", "calendar_hold", "nota_draft" ]),
      payload_json: z.record(z.any()),
      metadata_json: z.record(z.any()).optional(),
      proposed_by: z.enum([ "manual", "ai_assistant", "automation_agent", "api" ]).optional()
    },
    outputSchema: {
      agent_action: z.object({
        id: z.string(),
        title: z.string(),
        status: z.string(),
        draft_type: z.string(),
        target_system: z.string()
      })
    }
  },
  async ({ workspace_slug: workspaceSlug, title, target_system: targetSystem, draft_type: draftType, payload_json: payloadJson, metadata_json: metadataJson, proposed_by: proposedBy }) => runTool(async () => {
    const agentAction = await client.createAgentAction({ workspaceSlug, title, targetSystem, draftType, payloadJson, metadataJson, proposedBy });
    return successResult({
      text: `Created agent action "${agentAction.title}" (${agentAction.id}) with status ${agentAction.status}.`,
      data: { agent_action: agentAction }
    });
  })
);

server.registerTool(
  "approve_agent_action",
  {
    title: "Approve Notae Agent Action",
    description: "Approve a pending Notae agent-action draft. Task drafts require destination_database_id; calendar drafts require destination_calendar_id.",
    inputSchema: {
      workspace_slug: z.string(),
      agent_action_id: z.string(),
      decision_comment: z.string().optional(),
      destination_database_id: z.string().optional(),
      destination_calendar_id: z.string().optional()
    },
    outputSchema: {
      agent_action: z.object({
        id: z.string(),
        status: z.string(),
        result_json: z.record(z.any()).nullable().optional()
      })
    }
  },
  async ({ workspace_slug: workspaceSlug, agent_action_id: agentActionId, decision_comment: decisionComment, destination_database_id: destinationDatabaseId, destination_calendar_id: destinationCalendarId }) => runTool(async () => {
    const agentAction = await client.approveAgentAction({
      workspaceSlug,
      agentActionId,
      decisionComment,
      destinationDatabaseId,
      destinationCalendarId
    });
    return successResult({
      text: `Approved agent action ${agentAction.id} with status ${agentAction.status}.`,
      data: { agent_action: agentAction }
    });
  })
);

const transport = new StdioServerTransport();
await server.connect(transport);

function successResult({ text, data }) {
  return {
    content: [ { type: "text", text } ],
    structuredContent: data
  };
}

async function runTool(callback) {
  try {
    return await callback();
  } catch (error) {
    return {
      content: [ { type: "text", text: formatError(error) } ],
      isError: true
    };
  }
}

function formatError(error) {
  if (error instanceof NotaeApiError && error.status) {
    return `Notae API error (${error.status}): ${error.message}`;
  }

  return error?.message || "Unknown Notae MCP server error";
}

function renderWorkspaces(workspaces) {
  if (!workspaces.length) return "No accessible Notae workspaces found.";
  return workspaces.map((workspace) => `- ${workspace.name} (${workspace.slug}) role=${workspace.role || "unknown"}`).join("\n");
}

function renderPages(pages) {
  if (!pages.length) return "No matching pages found.";
  return pages.map((page) => `- ${page.title} (${page.id}) permission=${page.permission_mode}`).join("\n");
}

function renderTaskLists(taskLists) {
  if (!taskLists.length) return "No task lists found.";
  return taskLists.map((taskList) => `- ${taskList.name} (${taskList.id}) rows=${taskList.row_count ?? 0}`).join("\n");
}

function renderCalendars(calendars) {
  if (!calendars.length) return "No calendars found.";
  return calendars
    .map((calendar) => `- ${calendar.name} (${calendar.id}) writable=${calendar.writable === false ? "no" : "yes"}`)
    .join("\n");
}

function renderCreatedCalendarEvent(result) {
  const event = result?.event;
  if (!event) return "Created calendar event.";

  const lines = [
    `Created event "${event.title}" (${event.id}) on calendar ${event.calendar_id}.`,
    event.starts_at_utc && event.ends_at_utc ? `Time: ${event.starts_at_utc} -> ${event.ends_at_utc}` : null,
    result?.warning ? `Warning: ${result.warning}` : null,
    result?.url ? `Open: ${result.url}` : null
  ].filter(Boolean);

  return lines.join("\n");
}

function renderAgentActions(agentActions) {
  if (!agentActions.length) return "No agent actions found.";
  return agentActions.map((agentAction) => `- ${agentAction.title} (${agentAction.id}) ${agentAction.draft_type}/${agentAction.target_system} status=${agentAction.status}`).join("\n");
}
