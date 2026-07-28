import { Baloo_2, Inter } from "next/font/google";
import "./globals.css";
import { CartProvider } from "../context/CartContext";
import { AuthProvider } from "../context/AuthContext";
import BottomNav from "../components/BottomNav";
const baloo = Baloo_2({ subsets: ["latin"], variable: "--font-display", weight: ["600", "700", "800"] });
const inter = Inter({ subsets: ["latin"], variable: "--font-body", weight: ["400", "500", "600", "700"] });
export const metadata = {
  title: "Cão&Cão · Tudo para o seu pet",
  description: "Ração, brinquedos e acessórios para o seu melhor amigo, com entrega rápida.",
};
export default function RootLayout({ children }) {
  return (
    <html lang="pt-BR" className={`${baloo.variable} ${inter.variable}`}>
      <body className="font-body">
        <AuthProvider>
          <CartProvider>
            <div className="pb-16 md:pb-0">{children}</div>
            <footer
              style={{
                textAlign: "center",
                fontSize: 11,
                color: "#a3a3a3",
                padding: "18px 16px 24px",
              }}
            >
              <a href="/politica-privacidade" style={{ textDecoration: "underline" }}>Política de Privacidade</a>
              <br />
              Desenvolvido por Fabrício da Silva França, para fins didáticos
            </footer>
            <BottomNav />

            <svg className="walking-dog" viewBox="0 0 150 85" aria-hidden="true">
              <defs>
                <linearGradient id="furBody" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="#E0A05C" />
                  <stop offset="100%" stopColor="#C17A3A" />
                </linearGradient>
                <linearGradient id="furHead" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="#E8AC68" />
                  <stop offset="100%" stopColor="#CC8443" />
                </linearGradient>
              </defs>

              {/* Rabo, balançando */}
              <path className="dog-tail" d="M14 32 Q -10 14 4 2 Q 10 0 12 6 Q 2 14 18 30 Z" fill="#B8763E" />

              {/* Silhueta única do corpo + peito + pescoço, curva contínua (sem "costura" visível) */}
              <path
                d="M20 55
                   C 8 55 2 46 4 38
                   C 6 28 18 20 34 19
                   C 42 18 50 20 58 24
                   C 66 16 78 10 92 10
                   C 100 10 105 15 106 22
                   C 116 24 124 32 124 42
                   C 124 52 116 58 104 58
                   L 32 58
                   C 26 58 22 57 20 55 Z"
                fill="url(#furBody)"
              />
              {/* Barriga mais clara, pra dar volume */}
              <path d="M22 50 C 34 58 70 60 100 55 C 96 62 30 63 22 50 Z" fill="#F3C58A" opacity="0.85" />

              {/* Patas traseiras */}
              <rect className="leg leg-back-1" x="26" y="54" width="10" height="21" rx="5" fill="#8A5223" />
              <rect className="leg leg-back-2" x="42" y="54" width="10" height="21" rx="5" fill="#8A5223" />
              {/* Patas dianteiras */}
              <rect className="leg leg-front-1" x="84" y="54" width="10" height="21" rx="5" fill="#8A5223" />
              <rect className="leg leg-front-2" x="100" y="54" width="10" height="21" rx="5" fill="#8A5223" />
              {/* Patinhas (pés) */}
              <ellipse className="leg leg-back-1" cx="31" cy="76" rx="6" ry="3" fill="#5C3417" />
              <ellipse className="leg leg-back-2" cx="47" cy="76" rx="6" ry="3" fill="#5C3417" />
              <ellipse className="leg leg-front-1" cx="89" cy="76" rx="6" ry="3" fill="#5C3417" />
              <ellipse className="leg leg-front-2" cx="105" cy="76" rx="6" ry="3" fill="#5C3417" />

              {/* Cabeça, com focinho alongado (mais realista que um círculo só) */}
              <path
                d="M78 6
                   C 92 2 106 6 112 16
                   C 118 18 132 20 138 27
                   C 142 31 141 37 136 38
                   C 130 39 122 36 116 32
                   C 112 36 104 38 96 36
                   C 84 34 76 24 76 14
                   C 76 10 77 7 78 6 Z"
                fill="url(#furHead)"
              />
              {/* Focinho mais claro */}
              <path d="M116 22 C 126 22 136 26 138 30 C 134 33 122 32 114 28 Z" fill="#F3C58A" />
              {/* Nariz */}
              <ellipse cx="136" cy="29" rx="3.4" ry="2.6" fill="#241408" />
              {/* Boca, um traço simples */}
              <path d="M124 34 Q 120 38 114 36" stroke="#5C3417" strokeWidth="1.6" fill="none" strokeLinecap="round" />

              {/* Orelha caída */}
              <path d="M92 4 C 78 2 70 12 74 26 C 82 24 92 16 96 8 Z" fill="#8A5223" />

              {/* Olho, com brilho */}
              <circle cx="100" cy="18" r="3.6" fill="#241408" />
              <circle cx="101.3" cy="16.5" r="1.2" fill="#fff" />
              {/* Sobrancelha, dá expressão */}
              <path d="M94 12 Q 100 9 106 12" stroke="#5C3417" strokeWidth="1.4" fill="none" strokeLinecap="round" />

              {/* Coleira, combinando com a marca */}
              <path d="M86 40 Q 100 46 114 40 L 114 45 Q 100 51 86 45 Z" fill="#FF6B1A" />
              <circle cx="100" cy="47" r="2.6" fill="#FFD9B8" />
            </svg>
          </CartProvider>
        </AuthProvider>
      </body>
    </html>
  );
}
