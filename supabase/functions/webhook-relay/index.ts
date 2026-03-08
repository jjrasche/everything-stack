import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const authHeader = req.headers.get("x-webhook-secret");
  const expectedSecret = Deno.env.get("WEBHOOK_SECRET");
  if (expectedSecret && authHeader !== expectedSecret) {
    return new Response("Unauthorized", { status: 401 });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  const sourceType = body.source_type as string | undefined;
  const sourceId = body.source_id as string | undefined;
  const contentText = body.content_text as string | undefined;

  if (!sourceType || !sourceId || !contentText) {
    return new Response(
      JSON.stringify({
        error: "Missing required fields: source_type, source_id, content_text",
      }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  const { error } = await supabase.from("comm_events").upsert(
    {
      source_type: sourceType,
      source_id: sourceId,
      content_text: contentText,
      channel_id: body.channel_id ?? null,
      channel_name: body.channel_name ?? null,
      sender_id: body.sender_id ?? null,
      sender_name: body.sender_name ?? null,
      content_type: body.content_type ?? "message",
      raw_payload: body,
    },
    { onConflict: "source_type,source_id" }
  );

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ status: "ok" }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
