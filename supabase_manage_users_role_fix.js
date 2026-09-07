import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

const supabase = createClient(supabaseUrl, supabaseServiceKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
});

function validRole(role) {
  return ["admin", "instructor", "student", "accountant", "staff"].includes(role);
}

function normalizeRole(role) {
  if (!role) return "student";
  const r = String(role).trim().toLowerCase();
  return validRole(r) ? r : "student";
}

Deno.serve(async (req) => {
  try {
    const body = await req.json();
    const {
      action,
      username,
      password,
      full_name,
      name_ar,
      contact_email,
      phone,
      join_date,
      role,
      ...rest
    } = body;

    if (!action) {
      return new Response(JSON.stringify({ error: "Action is required" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing auth header" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const auth = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));
    if (auth.error || !auth.data?.user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const current = await supabase
      .from("profiles")
      .select("role")
      .eq("id", auth.data.user.id)
      .single();

    if (current.error || !current.data) {
      return new Response(JSON.stringify({ error: "Current user not found" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (current.data.role !== "admin") {
      return new Response(JSON.stringify({ error: "Only admin can manage users" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (action === "create_user") {
      const finalRole = normalizeRole(role);

      if (!username || !password) {
        return new Response(JSON.stringify({ error: "Username and password are required" }), {
          status: 400,
          headers: { "Content-Type": "application/json" },
        });
      }

      const { data: existing } = await supabase
        .from("profiles")
        .select("id")
        .eq("username", username)
        .maybeSingle();

      if (existing) {
        return new Response(JSON.stringify({ error: "Username already exists" }), {
          status: 409,
          headers: { "Content-Type": "application/json" },
        });
      }

      const email = `${username}@dos-academy.local`;

      const { data: createdAuth, error: authError } = await supabase.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: {
          full_name: full_name || username,
          role: finalRole,
        },
      });

      if (authError || !createdAuth?.user) {
        return new Response(JSON.stringify({ error: authError?.message || "Failed to create auth user" }), {
          status: 400,
          headers: { "Content-Type": "application/json" },
        });
      }

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
        return new Response(JSON.stringify({ error: profileError.message || "Failed to create profile" }), {
          status: 400,
          headers: { "Content-Type": "application/json" },
        });
      }

      return new Response(JSON.stringify({ ok: true, user: createdAuth.user, role: finalRole }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (action === "delete_user") {
      const { profile_id, username: targetUsername } = body;

      if (!profile_id && !targetUsername) {
        return new Response(JSON.stringify({ error: "profile_id or username is required" }), {
          status: 400,
          headers: { "Content-Type": "application/json" },
        });
      }

      const userId = profile_id;
      if (userId) {
        const { error: deleteAuthError } = await supabase.auth.admin.deleteUser(userId);
        if (deleteAuthError) {
          return new Response(JSON.stringify({ error: deleteAuthError.message }), {
            status: 400,
            headers: { "Content-Type": "application/json" },
          });
        }
      }

      return new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (action === "reset_password") {
      const { profile_id, new_password } = body;

      if (!profile_id || !new_password) {
        return new Response(JSON.stringify({ error: "Profile ID and new password are required" }), {
          status: 400,
          headers: { "Content-Type": "application/json" },
        });
      }

      const { error } = await supabase.auth.admin.updateUserById(profile_id, {
        password: new_password,
      });

      if (error) {
        return new Response(JSON.stringify({ error: error.message }), {
          status: 400,
          headers: { "Content-Type": "application/json" },
        });
      }

      return new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ error: "Unsupported action" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message || "Unhandled error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
