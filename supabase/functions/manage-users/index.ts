import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !supabaseServiceKey) {
  throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be configured");
}

const supabase = createClient(supabaseUrl, supabaseServiceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function validRole(role: unknown) {
  return ["admin", "instructor", "student", "accountant", "staff"].includes(String(role));
}

function normalizeRole(role: unknown) {
  const normalized = String(role || "student").trim().toLowerCase();
  return validRole(normalized) ? normalized : "student";
}

function json(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  try {
    const body = await req.json();
    const { action, username, password, full_name, name_ar, contact_email, phone, join_date, role, ...rest } = body;
    if (!action) return json({ error: "Action is required" }, 400);

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Missing auth header" }, 401);
    const auth = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));
    if (auth.error || !auth.data?.user) return json({ error: "Unauthorized" }, 401);

    const { data: current, error: currentError } = await supabase
      .from("profiles")
      .select("role")
      .eq("id", auth.data.user.id)
      .single();
    if (currentError || !current) return json({ error: "Current user not found" }, 403);
    if (current.role !== "admin") return json({ error: "Only admin can manage users" }, 403);

    if (action === "create_user") {
      if (!username || !password) return json({ error: "Username and password are required" }, 400);
      const finalRole = normalizeRole(role);
      const { data: existing } = await supabase.from("profiles").select("id").eq("username", username).maybeSingle();
      if (existing) return json({ error: "Username already exists" }, 409);

      const { data: createdAuth, error: authError } = await supabase.auth.admin.createUser({
        email: `${username}@dos-academy.local`,
        password,
        email_confirm: true,
        user_metadata: { full_name: full_name || username, role: finalRole },
      });
      if (authError || !createdAuth?.user) return json({ error: authError?.message || "Failed to create auth user" }, 400);

      const { error: profileError } = await supabase.from("profiles").insert({
        id: createdAuth.user.id,
        username,
        full_name: full_name || username,
        name_ar: name_ar || "",
        contact_email: contact_email || "",
        phone: phone || "",
        role: finalRole,
        join_date: join_date || new Date().toISOString().slice(0, 10),
        ...rest,
      });
      if (profileError) {
        await supabase.auth.admin.deleteUser(createdAuth.user.id);
        return json({ error: profileError.message || "Failed to create profile" }, 400);
      }
      return json({ ok: true, user: createdAuth.user, role: finalRole });
    }

    if (action === "delete_user") {
      const { profile_id, username: targetUsername } = body;
      if (!profile_id && !targetUsername) return json({ error: "profile_id or username is required" }, 400);
      let userId = profile_id;
      if (!userId && targetUsername) {
        const { data: target } = await supabase.from("profiles").select("id").eq("username", targetUsername).maybeSingle();
        userId = target?.id;
      }
      if (!userId) return json({ error: "User not found" }, 404);
      const { error } = await supabase.auth.admin.deleteUser(userId);
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    if (action === "reset_password") {
      const { profile_id, new_password } = body;
      if (!profile_id || !new_password) return json({ error: "Profile ID and new password are required" }, 400);
      const { error } = await supabase.auth.admin.updateUserById(profile_id, { password: new_password });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    return json({ error: "Unsupported action" }, 400);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unhandled error" }, 500);
  }
});
