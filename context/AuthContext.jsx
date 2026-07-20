"use client";

import { createContext, useContext, useEffect, useState } from "react";
import { supabase } from "../lib/supabaseClient";

const STORAGE_KEY = "loja:customer-id";
const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [customer, setCustomer] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    restoreSession();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function restoreSession() {
    try {
      const savedId = localStorage.getItem(STORAGE_KEY);
      if (savedId) {
        const { data } = await supabase.from("customers").select("*").eq("id", savedId).maybeSingle();
        if (data) setCustomer(data);
      }
    } finally {
      setLoading(false);
    }
  }

  async function loginWithPhone(phone) {
    const cleanPhone = phone.replace(/\D/g, "");

    const { data: existing } = await supabase
      .from("customers")
      .select("*")
      .eq("phone", cleanPhone)
      .maybeSingle();

    let customerRecord = existing;

    if (!customerRecord) {
      const { data: created, error } = await supabase
        .from("customers")
        .insert({ phone: cleanPhone, name: "", stage: "lead", source: "site" })
        .select("*")
        .single();
      if (error) throw error;
      customerRecord = created;
    }

    localStorage.setItem(STORAGE_KEY, customerRecord.id);
    setCustomer(customerRecord);
    return customerRecord;
  }

  async function logout() {
    localStorage.removeItem(STORAGE_KEY);
    setCustomer(null);
  }

  return (
    <AuthContext.Provider value={{ customer, loading, loginWithPhone, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth precisa estar dentro de <AuthProvider>");
  return ctx;
}
