import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const FROM_EMAIL = Deno.env.get("DOS_FROM_EMAIL") || "DOS Academy <info@dos-eg.com>";
const APP_URL = Deno.env.get("DOS_APP_URL") || "https://dos-info-eg.github.io/Drei-Online-Spezialisten/";

function json(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } });
}

function escapeHtml(value: unknown) {
  return String(value ?? "-").replace(/[&<>'"]/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "'": "&#39;",
    '"': "&quot;",
  }[character] || character));
}

Deno.serve(async (req) => {
  try {
    if (!RESEND_API_KEY) return json({ error: "RESEND_API_KEY is not configured" }, 503);
    const body = await req.json();
    const { full_name, email, phone, qualification, governorate, course } = body;
    if (!full_name || !email || !phone || !course) return json({ error: "Required application fields are missing" }, 400);
    const safeName = escapeHtml(full_name);
    const safeEmail = escapeHtml(email);
    const safePhone = escapeHtml(phone);
    const safeQualification = escapeHtml(qualification);
    const safeGovernorate = escapeHtml(governorate);
    const safeCourse = escapeHtml(course);

    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${RESEND_API_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: FROM_EMAIL,
        to: [email],
        subject: "DOS Akademie | Ihre Reservierung wurde empfangen",
        html: `<!doctype html><html lang="de"><body style="margin:0;background:#f5f2ec;font-family:Arial,sans-serif;color:#10233f"><div style="max-width:640px;margin:32px auto;background:#fff;border:1px solid #e6dfd4;border-radius:18px;overflow:hidden"><div style="padding:28px;background:#0b1f3a;text-align:center"><img src="${APP_URL}dos-full-logo.svg" alt="DOS Academy" style="max-width:300px;background:#fff;border-radius:10px;padding:8px"></div><div style="padding:30px"><p style="color:#c8283a;font-weight:700">Herzlich willkommen bei DOS</p><h1 style="font-size:26px;margin:0 0 14px">Vielen Dank, ${safeName}.</h1><p style="line-height:1.8;color:#596777">Ihre Kursreservierung ist bei uns eingegangen. Unser Team meldet sich persönlich mit dem passenden Starttermin und den nächsten Schritten.</p><div style="background:#f8f5ef;border-radius:12px;padding:18px;line-height:2"><b>Ihre Daten</b><br>Kurs: ${safeCourse}<br>E-Mail: ${safeEmail}<br>Telefon: ${safePhone}<br>Qualifikation: ${safeQualification}<br>Ort: ${safeGovernorate}</div><h2 style="font-size:18px;margin:24px 0 8px">Das erwartet Sie im DOS-Lernportal</h2><p style="line-height:1.8;color:#596777">Live-Unterricht, vier Sprachfertigkeiten, kleine Gruppen, persönliche Betreuung und Zugang zum DOS-Lernportal.</p><p style="margin-top:24px;color:#8a610d;font-weight:700">Lernen. Verstehen. Umsetzen.</p></div></div></body></html>`,
      }),
    });
    if (!response.ok) return json({ error: await response.text() }, 502);
    return json({ ok: true });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unhandled error" }, 500);
  }
});
