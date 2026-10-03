import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store, private, max-age=0",
  Vary: "Origin",
};

function json(data: Record<string, string>, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !anonKey || !serviceKey) {
  throw new Error("Supabase URL, anon key, and service role key must be configured");
}

const serviceClient = createClient(supabaseUrl, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return json({ error: "Authentication required" }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) return json({ error: "Invalid session" }, 401);

  let storagePath: unknown;
  try {
    ({ storagePath } = await request.json());
  } catch {
    return json({ error: "Invalid request body" }, 400);
  }
  if (typeof storagePath !== "string" || !storagePath || storagePath.includes("..") || storagePath.startsWith("/")) {
    return json({ error: "Invalid library file" }, 400);
  }

  const { data: profile, error: profileError } = await serviceClient
    .from("profiles")
    .select("role")
    .eq("id", authData.user.id)
    .maybeSingle();
  if (profileError || !profile) return json({ error: "User profile not found" }, 403);

  const { data: book, error: bookError } = await serviceClient
    .from("course_library")
    .select("title, storage_path, visible, instructor_profile_id, library_type, student_download_enabled")
    .eq("storage_path", storagePath)
    .maybeSingle();
  if (bookError || !book) return json({ error: "Library item not found" }, 404);

  if (profile.role === "instructor" && book.instructor_profile_id !== authData.user.id) {
    return json({ error: "You can only view files you uploaded" }, 403);
  }

  if (profile.role === "student") {
    if (!book.visible) return json({ error: "This library item is not available" }, 403);
    if (book.library_type === "paper" && book.student_download_enabled === false) {
      return json({ error: "Downloading this paper file is not allowed" }, 403);
    }
    const { data: student, error: studentError } = await serviceClient
      .from("students")
      .select("library_access_enabled")
      .eq("profile_id", authData.user.id)
      .maybeSingle();
    if (studentError || !student?.library_access_enabled) return json({ error: "Library access is not enabled" }, 403);
  } else if (profile.role !== "admin" && profile.role !== "instructor") {
    return json({ error: "This account cannot view library files" }, 403);
  }

  const { data: file, error: fileError } = await serviceClient.storage
    .from("course-library")
    .download(storagePath);
  if (fileError || !file) return json({ error: "Unable to load library file" }, 404);

  const extension = storagePath.split(".").pop()?.toLowerCase() || "";
  const contentType = file.type || (extension === "html" || extension === "htm" ? "text/html; charset=utf-8" : "application/octet-stream");
  const filename = encodeURIComponent(book.title || "library-item");
  return new Response(file.stream(), {
    headers: {
      ...corsHeaders,
      "Content-Type": contentType,
      "Content-Disposition": `inline; filename*=UTF-8''${filename}`,
      "X-Content-Type-Options": "nosniff",
      "Content-Security-Policy": "default-src 'none'; img-src 'self' data: blob: https:; style-src 'self' 'unsafe-inline' https:; font-src 'self' data: https:; script-src 'self' 'unsafe-inline' https:; media-src 'self' blob: https:; frame-ancestors 'self'; base-uri https: http: blob:",
    },
  });
});