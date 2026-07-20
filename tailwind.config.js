/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["./app/**/*.{js,jsx}", "./components/**/*.{js,jsx}"],
  theme: {
    extend: {
      colors: {
        brand: {
          DEFAULT: "#FF6B1A",
          dark: "#E4580D",
          light: "#FFE8D6",
        },
        ink: {
          DEFAULT: "#16243D",
          soft: "#3A4A63",
        },
        cream: "#FFFBF6",
        success: "#2F9E58",
      },
      fontFamily: {
        display: ["var(--font-display)"],
        body: ["var(--font-body)"],
      },
      borderRadius: {
        xl2: "1.25rem",
      },
    },
  },
  plugins: [],
};
