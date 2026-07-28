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
            <span className="walking-dog" aria-hidden="true">🐕</span>
          </CartProvider>
        </AuthProvider>

        <style jsx global>{`
          .walking-dog {
            position: fixed;
            bottom: 72px;
            left: -48px;
            font-size: 30px;
            line-height: 1;
            z-index: 20;
            pointer-events: none;
            animation: walk-across 16s linear infinite, bob 0.5s ease-in-out infinite;
          }
          @keyframes walk-across {
            0% { left: -48px; }
            45% { left: calc(100vw + 48px); }
            45.01% { left: -48px; opacity: 0; }
            48% { opacity: 0; }
            48.01% { opacity: 1; }
            100% { left: -48px; opacity: 1; }
          }
          @keyframes bob {
            0%, 100% { transform: translateY(0) scaleX(-1); }
            50% { transform: translateY(-4px) scaleX(-1); }
          }
          @media (min-width: 768px) {
            .walking-dog { display: none; }
          }
        `}</style>
      </body>
    </html>
  );
}
