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

            <svg className="walking-dog" viewBox="0 0 100 60" aria-hidden="true">
              {/* Rabo, balançando */}
              <path className="dog-tail" d="M10 22 Q -6 8 4 2" stroke="#B8763E" strokeWidth="6" fill="none" strokeLinecap="round" />

              {/* Patas traseiras */}
              <rect className="leg leg-back-1" x="20" y="38" width="8" height="15" rx="4" fill="#8A5223" />
              <rect className="leg leg-back-2" x="32" y="38" width="8" height="15" rx="4" fill="#8A5223" />

              {/* Corpo */}
              <ellipse cx="50" cy="34" rx="30" ry="16" fill="#D98C4A" />
              <ellipse cx="50" cy="42" rx="26" ry="8" fill="#F3C58A" />

              {/* Patas dianteiras */}
              <rect className="leg leg-front-1" x="58" y="38" width="8" height="15" rx="4" fill="#8A5223" />
              <rect className="leg leg-front-2" x="70" y="38" width="8" height="15" rx="4" fill="#8A5223" />

              {/* Cabeça (bem maior, estilo fofo) */}
              <circle cx="80" cy="20" r="17" fill="#D98C4A" />
              <ellipse cx="93" cy="24" rx="8" ry="6" fill="#F3C58A" />

              {/* Orelha caída */}
              <path d="M70 8 Q 58 10 62 26 Q 70 22 74 12 Z" fill="#8A5223" />

              {/* Focinho e olho */}
              <ellipse cx="98" cy="26" rx="3" ry="2.4" fill="#3B2416" />
              <circle cx="83" cy="14" r="2.6" fill="#3B2416" />
              <circle cx="84" cy="13" r="0.9" fill="#fff" />

              {/* Coleira, combinando com a marca */}
              <rect x="72" y="30" width="18" height="4.5" rx="2.2" fill="#FF6B1A" />
              <circle cx="81" cy="36" r="2.2" fill="#FFD9B8" />
            </svg>
          </CartProvider>
        </AuthProvider>
      </body>
    </html>
  );
}
