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
              {/* Rabo */}
              <path className="dog-tail" d="M8 24 Q -4 14 0 6" stroke="#8B4A24" strokeWidth="5" fill="none" strokeLinecap="round" />
              {/* Corpo */}
              <ellipse cx="42" cy="32" rx="28" ry="15" fill="#C4763A" />
              <ellipse cx="42" cy="38" rx="24" ry="7" fill="#E8A968" />
              {/* Patas traseiras */}
              <rect className="leg leg-back-1" x="18" y="38" width="7" height="16" rx="3.5" fill="#8B4A24" />
              <rect className="leg leg-back-2" x="30" y="38" width="7" height="16" rx="3.5" fill="#8B4A24" />
              {/* Patas dianteiras */}
              <rect className="leg leg-front-1" x="54" y="38" width="7" height="16" rx="3.5" fill="#8B4A24" />
              <rect className="leg leg-front-2" x="65" y="38" width="7" height="16" rx="3.5" fill="#8B4A24" />
              {/* Cabeça */}
              <circle cx="76" cy="20" r="14" fill="#C4763A" />
              <ellipse cx="87" cy="24" rx="7" ry="5" fill="#E8A968" />
              {/* Orelha */}
              <path d="M70 10 Q 62 8 63 20 Q 68 18 72 14 Z" fill="#8B4A24" />
              {/* Focinho e olho */}
              <circle cx="92" cy="25" r="2" fill="#3B2416" />
              <circle cx="80" cy="14" r="2.2" fill="#3B2416" />
              {/* Coleira laranja (combina com a marca) */}
              <rect x="68" y="27" width="16" height="4" rx="2" fill="#FF6B1A" />
              <circle cx="76" cy="32" r="2" fill="#FFD9B8" />
            </svg>
          </CartProvider>
        </AuthProvider>
      </body>
    </html>
  );
}
