"use client";

import { useEffect, useState } from "react";
import Header from "../../components/Header";
import { supabase } from "../../lib/supabaseClient";

export default function PoliticaPrivacidadePage() {
  const [texto, setTexto] = useState("");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function loadPolitica() {
      const { data } = await supabase.from("juridico_lgpd_politica").select("texto").eq("id", "atual").maybeSingle();
      setTexto(data?.texto || "");
      setLoading(false);
    }
    loadPolitica();
  }, []);

  return (
    <div className="min-h-screen bg-cream">
      <Header />
      <div className="mx-auto max-w-2xl px-4 py-8">
        <h1 className="font-display text-2xl font-extrabold text-ink">Política de Privacidade</h1>

        {loading ? (
          <p className="mt-4 text-sm text-ink-soft">Carregando…</p>
        ) : !texto ? (
          <p className="mt-4 text-sm text-ink-soft">A política de privacidade ainda não foi cadastrada.</p>
        ) : (
          <div className="mt-4 whitespace-pre-line text-sm leading-relaxed text-ink-soft">
            {texto}
          </div>
        )}
      </div>
    </div>
  );
}
