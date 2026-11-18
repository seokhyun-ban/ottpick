// 오티티픽 TMDB 프록시 (Supabase Edge Function, 이름: tmdb)
// 앱은 TMDB 키 없이 이 함수만 부르고, 키는 Supabase 비밀값(TMDB_TOKEN)에만 보관한다.
// 비밀값: TMDB 설정 → API 의 "API 읽기 액세스 토큰"(긴 토큰)을 TMDB_TOKEN 으로 저장.

const ALLOW = [
  /^\/3\/search\/multi$/,
  /^\/3\/trending\/all\/week$/,
  /^\/3\/discover\/(movie|tv)$/,
  /^\/3\/(movie|tv)\/\d+\/(recommendations|watch\/providers)$/,
  /^\/3\/watch\/providers\/(movie|tv)$/,
];

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "GET") return new Response("method not allowed", { status: 405, headers: cors });

  const url = new URL(req.url);
  const path = url.pathname.replace(/^.*?\/tmdb(?=\/)/, ""); // /tmdb/3/... → /3/...
  if (!ALLOW.some((r) => r.test(path))) {
    return new Response(JSON.stringify({ error: "not allowed" }), {
      status: 403, headers: { ...cors, "content-type": "application/json" },
    });
  }

  const token = Deno.env.get("TMDB_TOKEN");
  if (!token) {
    return new Response(JSON.stringify({ error: "TMDB_TOKEN missing" }), {
      status: 500, headers: { ...cors, "content-type": "application/json" },
    });
  }

  const q = new URLSearchParams(url.search);
  q.delete("api_key");
  const r = await fetch(`https://api.themoviedb.org${path}?${q}`, {
    headers: { Authorization: `Bearer ${token}`, accept: "application/json" },
  });
  return new Response(await r.text(), {
    status: r.status,
    headers: { ...cors, "content-type": "application/json", "cache-control": "public, max-age=1800" },
  });
});
