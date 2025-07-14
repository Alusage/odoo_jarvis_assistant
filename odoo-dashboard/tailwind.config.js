/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx,xml}",
  ],
  theme: {
    extend: {
      colors: {
        primary: {
          50: '#f3f1f9',
          100: '#e7e4f2',
          200: '#d3cde7',
          300: '#b5aad5',
          400: '#9380c0',
          500: '#7D6CA8',
          600: '#6b5b95',
          700: '#5a4b7c',
          800: '#4d4067',
          900: '#423757',
          950: '#2a1f39'
        },
        success: {
          DEFAULT: '#4CAF50',
          light: '#81C784',
          dark: '#388E3C'
        },
        error: {
          DEFAULT: '#F44336',
          light: '#E57373',
          dark: '#D32F2F'
        },
        warning: {
          DEFAULT: '#FF9800',
          light: '#FFB74D',
          dark: '#F57C00'
        },
        info: {
          DEFAULT: '#2196F3',
          light: '#64B5F6',
          dark: '#1976D2'
        },
        teal: {
          DEFAULT: '#26A69A',
          light: '#4DB6AC',
          dark: '#00695C'
        }
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'Consolas', 'monospace']
      },
      boxShadow: {
        'card': '0 1px 3px 0 rgba(0, 0, 0, 0.1), 0 1px 2px 0 rgba(0, 0, 0, 0.06)',
        'card-hover': '0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06)',
        'modal': '0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04)'
      },
      animation: {
        'fade-in': 'fadeIn 0.3s ease-in-out',
        'slide-in-right': 'slideInRight 0.3s ease-out',
        'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite'
      },
      keyframes: {
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' }
        },
        slideInRight: {
          '0%': { transform: 'translateX(100%)' },
          '100%': { transform: 'translateX(0)' }
        }
      },
      screens: {
        'xs': '475px'
      }
    },
  },
  plugins: [
    require('@tailwindcss/forms')
  ],
}