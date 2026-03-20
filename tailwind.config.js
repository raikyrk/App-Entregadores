/** @type {import('tailwindcss').Config} */
module.exports = {
    content: [
      "./src/**/*.{js,jsx,ts,tsx}",
    ],
    theme: {
      extend: {
        colors: {
          aogosto: {
            orange: '#F28C38',
            dark: '#1A202C'
          }
        }
      },
    },
    plugins: [],
  }