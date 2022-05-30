const colors = require('tailwindcss/colors');

module.exports = {
  content: [
    './pages/**/*.{js,ts,jsx,tsx}',
    './lib/**/*.{js,ts,jsx,tsx}',
    './components/**/*.{js,ts,jsx,tsx}',
  ],
  theme: {
    extend: {
      colors: {
        ...colors,
        gray: colors.stone,
        blue: colors.indigo,
      },
      maxWidth: {
        '33':'33%',
        '60':'60%',
        '40':'40%'
      }
    },
  },
  plugins: [require('@tailwindcss/typography')],
};
